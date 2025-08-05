#!/bin/bash

# MongoDB X.509 인증서 생성 스크립트
# AWS Security 권장사항에 따른 인증서 기반 인증 설정

set -e

CERT_DIR="./mongodb-certificates"
CA_KEY_FILE="$CERT_DIR/ca-key.pem"
CA_CERT_FILE="$CERT_DIR/ca-cert.pem"
SERVER_KEY_FILE="$CERT_DIR/server-key.pem"
SERVER_CERT_FILE="$CERT_DIR/server-cert.pem"
CLIENT_KEY_FILE="$CERT_DIR/client-key.pem"
CLIENT_CERT_FILE="$CERT_DIR/client-cert.pem"

# MongoDB 클러스터 정보
MONGODB_CLUSTER_NAME="mongodb-sharded"
MONGODB_NAMESPACE="percona-mongodb"
MONGODB_DOMAIN="cluster.local"

echo "🔐 MongoDB X.509 인증서 생성 시작..."
echo "========================================"

# 인증서 디렉토리 생성
mkdir -p $CERT_DIR
cd $CERT_DIR

# 1. CA (Certificate Authority) 생성
echo "1. CA (Certificate Authority) 생성 중..."

# CA 개인키 생성
openssl genrsa -out ca-key.pem 4096

# CA 인증서 생성
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem -subj "/C=KR/ST=Seoul/L=Seoul/O=MongoDB-Cluster/OU=Database/CN=MongoDB-CA"

echo "✅ CA 인증서 생성 완료"

# 2. 서버 인증서 생성 (MongoDB 서버용)
echo ""
echo "2. MongoDB 서버 인증서 생성 중..."

# 서버 개인키 생성
openssl genrsa -out server-key.pem 4096

# 서버 인증서 요청 생성
openssl req -new -key server-key.pem -out server.csr -subj "/C=KR/ST=Seoul/L=Seoul/O=MongoDB-Cluster/OU=Database/CN=mongodb-sharded-mongos.percona-mongodb.svc.cluster.local"

# SAN (Subject Alternative Names) 설정 파일 생성
cat > server-extensions.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = mongodb-sharded-mongos
DNS.2 = mongodb-sharded-mongos.percona-mongodb
DNS.3 = mongodb-sharded-mongos.percona-mongodb.svc
DNS.4 = mongodb-sharded-mongos.percona-mongodb.svc.cluster.local
DNS.5 = mongodb-sharded-rs0
DNS.6 = mongodb-sharded-rs0.percona-mongodb.svc.cluster.local
DNS.7 = mongodb-sharded-rs1
DNS.8 = mongodb-sharded-rs1.percona-mongodb.svc.cluster.local
DNS.9 = mongodb-sharded-cfg
DNS.10 = mongodb-sharded-cfg.percona-mongodb.svc.cluster.local
DNS.11 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# 서버 인증서 생성 (CA로 서명)
openssl x509 -req -in server.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -days 365 -extensions v3_req -extfile server-extensions.conf

# 서버용 PEM 파일 생성 (개인키 + 인증서)
cat server-key.pem server-cert.pem > server.pem

echo "✅ 서버 인증서 생성 완료"

# 3. 클라이언트 인증서 생성 (애플리케이션/사용자용)
echo ""
echo "3. 클라이언트 인증서 생성 중..."

# 관리자 클라이언트 인증서
openssl genrsa -out admin-client-key.pem 4096
openssl req -new -key admin-client-key.pem -out admin-client.csr -subj "/C=KR/ST=Seoul/L=Seoul/O=MongoDB-Cluster/OU=Database/CN=admin"
openssl x509 -req -in admin-client.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out admin-client-cert.pem -days 365
cat admin-client-key.pem admin-client-cert.pem > admin-client.pem

# 애플리케이션 클라이언트 인증서
openssl genrsa -out app-client-key.pem 4096
openssl req -new -key app-client-key.pem -out app-client.csr -subj "/C=KR/ST=Seoul/L=Seoul/O=MongoDB-Cluster/OU=Application/CN=mongodb-app-user"
openssl x509 -req -in app-client.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out app-client-cert.pem -days 365
cat app-client-key.pem app-client-cert.pem > app-client.pem

# 모니터링 클라이언트 인증서 (Exporter용)
openssl genrsa -out monitor-client-key.pem 4096
openssl req -new -key monitor-client-key.pem -out monitor-client.csr -subj "/C=KR/ST=Seoul/L=Seoul/O=MongoDB-Cluster/OU=Monitoring/CN=mongodb-monitor"
openssl x509 -req -in monitor-client.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out monitor-client-cert.pem -days 365
cat monitor-client-key.pem monitor-client-cert.pem > monitor-client.pem

echo "✅ 클라이언트 인증서 생성 완료"

# 4. 임시 파일 정리
echo ""
echo "4. 임시 파일 정리 중..."
rm -f *.csr *.srl server-extensions.conf

# 5. 인증서 정보 출력
echo ""
echo "5. 생성된 인증서 정보:"
echo "========================================"
echo "CA 인증서:"
openssl x509 -in ca-cert.pem -text -noout | grep -A 2 "Subject:"

echo ""
echo "서버 인증서:"
openssl x509 -in server-cert.pem -text -noout | grep -A 2 "Subject:"

echo ""
echo "관리자 클라이언트 인증서:"
openssl x509 -in admin-client-cert.pem -text -noout | grep -A 2 "Subject:"

echo ""
echo "애플리케이션 클라이언트 인증서:"
openssl x509 -in app-client-cert.pem -text -noout | grep -A 2 "Subject:"

echo ""
echo "모니터링 클라이언트 인증서:"
openssl x509 -in monitor-client-cert.pem -text -noout | grep -A 2 "Subject:"

# 6. 파일 권한 설정
echo ""
echo "6. 파일 권한 설정 중..."
chmod 600 *-key.pem *.pem
chmod 644 *-cert.pem ca-cert.pem

# 7. Kubernetes Secret 생성 스크립트 생성
echo ""
echo "7. Kubernetes Secret 생성 스크립트 생성 중..."
cat > ../create-mongodb-tls-secrets.sh << 'EOF'
#!/bin/bash

# MongoDB TLS Secrets 생성 스크립트
CERT_DIR="./mongodb-certificates"
NAMESPACE="percona-mongodb"

echo "🔐 MongoDB TLS Secrets 생성 중..."

# 네임스페이스 생성 (없으면)
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# CA 인증서 Secret
kubectl create secret generic mongodb-ca-cert \
  --from-file=ca.crt=$CERT_DIR/ca-cert.pem \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# 서버 TLS Secret
kubectl create secret tls mongodb-server-tls \
  --cert=$CERT_DIR/server-cert.pem \
  --key=$CERT_DIR/server-key.pem \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# 관리자 클라이언트 Secret
kubectl create secret tls mongodb-admin-client \
  --cert=$CERT_DIR/admin-client-cert.pem \
  --key=$CERT_DIR/admin-client-key.pem \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# 애플리케이션 클라이언트 Secret
kubectl create secret tls mongodb-app-client \
  --cert=$CERT_DIR/app-client-cert.pem \
  --key=$CERT_DIR/app-client-key.pem \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# 모니터링 클라이언트 Secret
kubectl create secret tls mongodb-monitor-client \
  --cert=$CERT_DIR/monitor-client-cert.pem \
  --key=$CERT_DIR/monitor-client-key.pem \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ MongoDB TLS Secrets 생성 완료"
EOF

chmod +x ../create-mongodb-tls-secrets.sh

echo ""
echo "========================================"
echo "✅ MongoDB X.509 인증서 생성 완료!"
echo "========================================"
echo ""
echo "생성된 파일들:"
echo "  📁 $CERT_DIR/"
echo "    🔐 ca-cert.pem (CA 인증서)"
echo "    🔐 ca-key.pem (CA 개인키)"
echo "    🔐 server.pem (서버용 통합 인증서)"
echo "    🔐 admin-client.pem (관리자 클라이언트 인증서)"
echo "    🔐 app-client.pem (애플리케이션 클라이언트 인증서)"
echo "    🔐 monitor-client.pem (모니터링 클라이언트 인증서)"
echo ""
echo "다음 단계:"
echo "  1. ./create-mongodb-tls-secrets.sh 실행"
echo "  2. MongoDB 클러스터에 X.509 인증 설정 적용"
echo "  3. 클라이언트 애플리케이션에 인증서 배포"
echo ""
echo "⚠️  주의사항:"
echo "  - 개인키 파일들을 안전하게 보관하세요"
echo "  - 프로덕션 환경에서는 적절한 CA를 사용하세요"
echo "  - 인증서 만료일을 추적하고 갱신하세요"

cd ..
