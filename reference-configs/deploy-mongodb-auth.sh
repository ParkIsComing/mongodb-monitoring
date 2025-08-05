#!/bin/bash

# MongoDB X.509 + SCRAM 인증 자동 배포 스크립트
# AWS Security 권장사항에 따른 인증 설정

set -e

NAMESPACE="percona-mongodb"
CLUSTER_NAME="mongodb-sharded"

echo "🔐 MongoDB 인증 설정 자동 배포 시작..."
echo "========================================"

# 1. 사전 요구사항 확인
echo "1. 사전 요구사항 확인 중..."

# kubectl 확인
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl이 설치되지 않았습니다."
    exit 1
fi

# openssl 확인
if ! command -v openssl &> /dev/null; then
    echo "❌ openssl이 설치되지 않았습니다."
    exit 1
fi

# Kubernetes 클러스터 연결 확인
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes 클러스터에 연결할 수 없습니다."
    echo "   aws eks update-kubeconfig --region us-east-1 --name mongodb-cluster"
    exit 1
fi

echo "✅ 사전 요구사항 확인 완료"

# 2. 네임스페이스 생성
echo ""
echo "2. 네임스페이스 생성 중..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace $NAMESPACE name=$NAMESPACE --overwrite
echo "✅ 네임스페이스 생성 완료"

# 3. X.509 인증서 생성
echo ""
echo "3. X.509 인증서 생성 중..."
if [ ! -f "./generate-mongodb-certificates.sh" ]; then
    echo "❌ generate-mongodb-certificates.sh 파일이 없습니다."
    exit 1
fi

chmod +x ./generate-mongodb-certificates.sh
./generate-mongodb-certificates.sh

echo "✅ X.509 인증서 생성 완료"

# 4. Kubernetes Secrets 생성
echo ""
echo "4. Kubernetes Secrets 생성 중..."
if [ ! -f "./create-mongodb-tls-secrets.sh" ]; then
    echo "❌ create-mongodb-tls-secrets.sh 파일이 없습니다."
    exit 1
fi

chmod +x ./create-mongodb-tls-secrets.sh
./create-mongodb-tls-secrets.sh

echo "✅ Kubernetes Secrets 생성 완료"

# 5. 암호화된 스토리지 클래스 생성
echo ""
echo "5. 암호화된 스토리지 클래스 생성 중..."
kubectl apply -f storage-class-encrypted.yaml
echo "✅ 스토리지 클래스 생성 완료"

# 6. MongoDB 사용자 시크릿 생성
echo ""
echo "6. MongoDB 사용자 시크릿 생성 중..."

# 임시 패스워드 생성 및 시크릿 생성
cat > temp-mongodb-users.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-sharded-users
  namespace: $NAMESPACE
type: Opaque
stringData:
  MONGODB_DATABASE_ADMIN_USER: "databaseAdmin"
  MONGODB_DATABASE_ADMIN_PASSWORD: "$(openssl rand -base64 32 | tr -d '\n')"
  MONGODB_CLUSTER_ADMIN_USER: "clusterAdmin"
  MONGODB_CLUSTER_ADMIN_PASSWORD: "$(openssl rand -base64 32 | tr -d '\n')"
  MONGODB_BACKUP_USER: "backupUser"
  MONGODB_BACKUP_PASSWORD: "$(openssl rand -base64 32 | tr -d '\n')"
  MONGODB_CLUSTER_MONITOR_USER: "clusterMonitor"
  MONGODB_CLUSTER_MONITOR_PASSWORD: "$(openssl rand -base64 32 | tr -d '\n')"
  MONGODB_APPLICATION_USER: "appUser"
  MONGODB_APPLICATION_PASSWORD: "$(openssl rand -base64 32 | tr -d '\n')"
  MONGODB_READONLY_USER: "readOnlyUser"
  MONGODB_READONLY_PASSWORD: "$(openssl rand -base64 32 | tr -d '\n')"
EOF

kubectl apply -f temp-mongodb-users.yaml
rm temp-mongodb-users.yaml

echo "✅ MongoDB 사용자 시크릿 생성 완료"

# 7. 네트워크 정책 적용
echo ""
echo "7. 네트워크 정책 적용 중..."
if [ -f "./mongodb-network-policy.yaml" ]; then
    kubectl apply -f mongodb-network-policy.yaml
    echo "✅ 네트워크 정책 적용 완료"
else
    echo "⚠️  mongodb-network-policy.yaml 파일이 없습니다. 건너뜁니다."
fi

# 8. MongoDB 클러스터 배포
echo ""
echo "8. MongoDB 클러스터 배포 중..."
kubectl apply -f mongodb-cluster-x509-auth.yaml

echo "MongoDB 클러스터 배포 시작됨. 준비 상태 확인 중..."

# 클러스터 준비 대기
timeout=600  # 10분 타임아웃
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get psmdb $CLUSTER_NAME -n $NAMESPACE -o jsonpath='{.status.state}' 2>/dev/null | grep -q "ready"; then
        echo "✅ MongoDB 클러스터 준비 완료"
        break
    fi
    
    echo "MongoDB 클러스터 준비 중... (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    echo "⚠️  MongoDB 클러스터 준비 타임아웃. 수동으로 상태를 확인하세요."
    echo "   kubectl get psmdb -n $NAMESPACE"
    echo "   kubectl describe psmdb $CLUSTER_NAME -n $NAMESPACE"
fi

# 9. 사용자 설정 적용
echo ""
echo "9. MongoDB 사용자 설정 적용 중..."
kubectl apply -f mongodb-users-auth.yaml

echo "사용자 설정 Job 실행 중..."
kubectl wait --for=condition=complete job/mongodb-user-setup -n $NAMESPACE --timeout=300s || echo "⚠️  사용자 설정 Job 타임아웃"

# 10. MongoDB Exporter 배포
echo ""
echo "10. MongoDB Exporter 배포 중..."
kubectl apply -f mongodb-exporters.yaml
echo "✅ MongoDB Exporter 배포 완료"

# 11. 배포 상태 확인
echo ""
echo "11. 배포 상태 확인 중..."
echo ""
echo "MongoDB 클러스터 상태:"
kubectl get psmdb -n $NAMESPACE

echo ""
echo "MongoDB 파드 상태:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=percona-server-mongodb

echo ""
echo "MongoDB Exporter 상태:"
kubectl get pods -n $NAMESPACE -l app=mongodb-exporter

echo ""
echo "서비스 상태:"
kubectl get services -n $NAMESPACE

echo ""
echo "시크릿 상태:"
kubectl get secrets -n $NAMESPACE

# 12. 연결 정보 출력
echo ""
echo "========================================"
echo "✅ MongoDB 인증 설정 배포 완료!"
echo "========================================"
echo ""
echo "📋 연결 정보:"
echo ""
echo "🔐 X.509 인증서 기반 연결:"
echo "  - CA 인증서: ./mongodb-certificates/ca-cert.pem"
echo "  - 관리자 클라이언트: ./mongodb-certificates/admin-client.pem"
echo "  - 애플리케이션 클라이언트: ./mongodb-certificates/app-client.pem"
echo "  - 모니터링 클라이언트: ./mongodb-certificates/monitor-client.pem"
echo ""
echo "🔑 SCRAM 사용자 계정:"
echo "  - databaseAdmin (DB 관리)"
echo "  - clusterAdmin (클러스터 관리)"
echo "  - appUser (애플리케이션)"
echo "  - clusterMonitor (모니터링)"
echo "  - readOnlyUser (읽기 전용)"
echo "  - backupUser (백업)"
echo ""
echo "🌐 MongoDB 엔드포인트:"
echo "  - Mongos: mongodb-sharded-mongos.$NAMESPACE.svc.cluster.local:27017"
echo "  - TLS 필수, 인증 필수"
echo ""
echo "📊 모니터링 엔드포인트:"
echo "  - Mongos Exporter: mongodb-exporter-mongos.$NAMESPACE.svc.cluster.local:9216"
echo "  - RS0 Exporter: mongodb-exporter-rs0.$NAMESPACE.svc.cluster.local:9216"
echo "  - RS1 Exporter: mongodb-exporter-rs1.$NAMESPACE.svc.cluster.local:9216"
echo ""
echo "📖 사용법:"
echo "  - 클라이언트 연결 가이드: CLIENT-CONNECTION-GUIDE.md"
echo "  - 인증서 관리: ./mongodb-certificates/ 디렉토리"
echo "  - 패스워드 확인: kubectl get secret mongodb-sharded-users -n $NAMESPACE -o yaml"
echo ""
echo "⚠️  보안 주의사항:"
echo "  - 인증서 개인키를 안전하게 보관하세요"
echo "  - 정기적으로 패스워드를 변경하세요"
echo "  - 불필요한 사용자 계정을 삭제하세요"
echo "  - 접근 로그를 정기적으로 검토하세요"
echo ""
echo "🔍 상태 확인 명령어:"
echo "  kubectl get psmdb -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE mongodb-sharded-mongos-0"
echo "  kubectl exec -it -n $NAMESPACE mongodb-sharded-mongos-0 -- mongosh --help"

# 13. 연결 테스트 스크립트 생성
echo ""
echo "12. 연결 테스트 스크립트 생성 중..."
cat > test-mongodb-connection.sh << 'EOF'
#!/bin/bash

# MongoDB 연결 테스트 스크립트
NAMESPACE="percona-mongodb"
CERT_DIR="./mongodb-certificates"

echo "🔍 MongoDB 연결 테스트 시작..."

# X.509 인증서 기반 연결 테스트
echo ""
echo "1. X.509 인증서 기반 연결 테스트:"
kubectl run mongodb-test-x509 --rm -i --restart=Never \
  --image=percona/percona-server-mongodb:6.0.9-7 \
  --namespace=$NAMESPACE \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "mongodb-test",
        "image": "percona/percona-server-mongodb:6.0.9-7",
        "command": ["/bin/bash"],
        "args": ["-c", "mongosh --host mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017 --tls --tlsCAFile /certs/ca-cert.pem --tlsCertificateKeyFile /certs/admin-client.pem --authenticationDatabase '$external' --authenticationMechanism MONGODB-X509 --eval 'db.adminCommand({connectionStatus: 1})'"],
        "volumeMounts": [
          {
            "name": "certs",
            "mountPath": "/certs",
            "readOnly": true
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "certs",
        "projected": {
          "sources": [
            {
              "secret": {
                "name": "mongodb-ca-cert",
                "items": [{"key": "ca.crt", "path": "ca-cert.pem"}]
              }
            },
            {
              "secret": {
                "name": "mongodb-admin-client",
                "items": [
                  {"key": "tls.crt", "path": "admin-client-cert.pem"},
                  {"key": "tls.key", "path": "admin-client-key.pem"}
                ]
              }
            }
          ]
        }
      }
    ],
    "restartPolicy": "Never"
  }
}' || echo "X.509 연결 테스트 실패"

echo ""
echo "✅ 연결 테스트 완료"
EOF

chmod +x test-mongodb-connection.sh
echo "✅ 연결 테스트 스크립트 생성 완료: ./test-mongodb-connection.sh"

echo ""
echo "🎉 MongoDB 인증 설정 자동 배포가 완료되었습니다!"
echo "   연결 테스트를 실행하려면: ./test-mongodb-connection.sh"
