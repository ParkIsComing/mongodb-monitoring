# Unified MongoDB Monitoring with EKS, AMP, and AMG

이 프로젝트는 AWS EKS 환경에서 MongoDB에 대한 통합 모니터링 솔루션을 제공합니다. Amazon Managed Service for Prometheus (AMP)와 Amazon Managed Grafana (AMG)를 활용하여 포괄적인 MongoDB 모니터링 환경을 구축합니다.

## 지원하는 데이터베이스

- **MongoDB** - MongoDB Exporter를 통한 모니터링 (+ Percona MongoDB Operator 지원)
- 요구사항에 맞게 추가 가능

## 사전 요구사항

- AWS CLI (version 2.0.0 or later) 설치 및 인증 설정
- kubectl (version 1.23.0 or later) 설치
- helm (version 3.8.0 or later) 설치
- eksctl (version 0.123.0 or later) 설치
- CloudFormation 스택 생성 권한
- EKS 클러스터 생성 및 관리 권한

## 빠른 시작

### Step 0: EKS 클러스터 생성 (필요한 경우)

EKS 클러스터가 없는 경우, CloudFormation을 사용하여 클러스터를 생성합니다.

```bash
# 환경 변수 설정
export WORKSHOP_NAME=integrated-db-monitoring
export AWS_REGION=$(aws configure get region)
export VPC_CIDR="10.0.0.0/16"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# VPC가 없는 경우 먼저 VPC 생성 (networking-stack.yaml 필요)
aws cloudformation create-stack \
  --stack-name ${WORKSHOP_NAME}-network \
  --template-body file://networking-stack.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=${WORKSHOP_NAME} \
    ParameterKey=VpcCidr,ParameterValue=${VPC_CIDR} \
  --capabilities CAPABILITY_IAM \
  --region $AWS_REGION

# 네트워킹 스택 완료 대기 (약 5-10분)
aws cloudformation wait stack-create-complete \
  --stack-name ${WORKSHOP_NAME}-network \
  --region $AWS_REGION

# VPC ID와 서브넷 ID 가져오기
export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${WORKSHOP_NAME}-network \
  --query 'Stacks[0].Outputs[?OutputKey==`VPC`].OutputValue' \
  --output text --region $AWS_REGION)

export PRIVATE_SUBNETS=$(aws cloudformation describe-stacks \
  --stack-name ${WORKSHOP_NAME}-network \
  --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnets`].OutputValue' \
  --output text --region $AWS_REGION)

# EKS 클러스터 생성
aws cloudformation create-stack \
  --stack-name ${WORKSHOP_NAME}-eks \
  --template-body file://CloudFormation\ Templates/eks-stack-fixed.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=${WORKSHOP_NAME} \
    ParameterKey=VpcId,ParameterValue=${VPC_ID} \
    ParameterKey=PrivateSubnets,ParameterValue=\"${PRIVATE_SUBNETS}\" \
    ParameterKey=NodeInstanceType,ParameterValue=m5.xlarge \
    ParameterKey=NodeGroupDesiredSize,ParameterValue=3 \
  --capabilities CAPABILITY_IAM \
  --region $AWS_REGION

# EKS 스택 완료 대기 (약 15-20분)
aws cloudformation wait stack-create-complete \
  --stack-name ${WORKSHOP_NAME}-eks \
  --region $AWS_REGION

# 클러스터 이름 설정
export CLUSTER_NAME=${WORKSHOP_NAME}-eks

echo "EKS 클러스터 생성 완료: $CLUSTER_NAME"
```

> **참고**: 기존 EKS 클러스터가 있는 경우, 다음 명령어로 연결할 수 있습니다:
> ```bash
> export CLUSTER_NAME=your-existing-cluster-name
> aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
> kubectl get nodes
> ```

### 방법 1: 동적 값을 사용한 배포 (권장)

#### Step 1: 환경 변수 설정
```bash
# 기본 환경 변수 설정
export WORKSHOP_NAME=integrated-db-monitoring
export AWS_REGION=$(aws configure get region)
export VPC_CIDR="10.0.0.0/16"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 환경 설정 확인
echo "Workshop Name: $WORKSHOP_NAME"
echo "AWS Region: $AWS_REGION"
echo "AWS Account ID: $ACCOUNT_ID"
echo "Using VPC CIDR: $VPC_CIDR"
```

#### Step 2: 추가 모니터링 환경 변수 설정
```bash
# EKS 클러스터 이름 설정 (실제 클러스터 이름으로 변경)
export CLUSTER_NAME=${WORKSHOP_NAME}-eks

# AMP 워크스페이스 ID 설정 (실제 워크스페이스 ID로 변경 필요)
export AMP_WORKSPACE_ID=$(aws amp list-workspaces --query 'workspaces[0].workspaceId' --output text)

# ADOT Collector IAM 역할 ARN 설정
export ADOT_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/adot-collector-role

# MongoDB 설정 (선택사항)
export MONGODB_HOST=test-mongodb
export MONGODB_USERNAME=test
export MONGODB_PASSWORD=test
export MONGODB_DATABASE=admin
export MONGODB_PORT=27017

# 설정 확인
echo "Cluster Name: $CLUSTER_NAME"
echo "AMP Workspace ID: $AMP_WORKSPACE_ID"
echo "ADOT Role ARN: $ADOT_ROLE_ARN"
```

#### Step 3: EKS 클러스터 연결
```bash
# EKS 클러스터 kubeconfig 업데이트
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME

# 클러스터 연결 확인
kubectl get nodes
```

#### Step 4: Helm을 사용한 직접 배포

README의 "방법 2: Helm 직접 사용" 섹션을 참조하여 배포하세요.

### 방법 2: Helm 직접 사용 (권장)
```bash
# 환경 변수 설정 후 Helm으로 직접 배포
helm upgrade --install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --set aws.iam.adotRoleArn=$ADOT_ROLE_ARN \
  --set databases.mongodb.enabled=true \
  --set databases.mongodb.instances[0].host=$MONGODB_HOST \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD \
  --namespace observability \
  --create-namespace
```

### 방법 3: 통합 Helm 차트를 이용한 배포 (단계별 상세 가이드)

#### 1. 전체 인프라 배포 (CloudFormation)
```bash
# 네트워킹 스택 먼저 배포
aws cloudformation create-stack \
  --stack-name ${WORKSHOP_NAME}-network \
  --template-body file://networking-stack.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=${WORKSHOP_NAME} \
    ParameterKey=VpcCidr,ParameterValue=${VPC_CIDR} \
  --capabilities CAPABILITY_IAM

# 네트워킹 스택 완료 대기 (약 5-10분)
aws cloudformation wait stack-create-complete --stack-name ${WORKSHOP_NAME}-network --region us-east-1
```

#### 2. EKS 클러스터 연결
```bash
# EKS 클러스터 kubeconfig 업데이트
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME

# 클러스터 연결 확인
kubectl get nodes
```

#### 3. Helm 차트 의존성 업데이트
```bash
# 통합 DB 모니터링 차트 의존성 업데이트
helm dependency update ./helm-charts/db-monitoring

# MongoDB Percona Operator 차트 의존성 업데이트 (필요시)
helm dependency update ./helm-charts/mongodb-monitoring
```

#### 4. 통합 DB 모니터링 배포 (모든 데이터베이스 Exporter 포함)

##### MongoDB 모니터링 배포
```bash
# MongoDB 모니터링 - 동적 값 사용
helm install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --set databases.mongodb.instances[0].host=$MONGODB_HOST \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD \
  --set mongodb.enabled=true \
  --set adot.enabled=true

# 프로덕션 환경 - 동적 값 사용
helm install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --set aws.iam.adotRoleArn=$ADOT_ROLE_ARN
```

#### 5. MongoDB Percona Operator 배포 (선택사항)

MongoDB 클러스터 자체를 배포하려면:
```bash
# 자동 설치 스크립트 사용
cd helm-charts
./install.sh

# 수동 설치 - 동적 값 사용
helm install mongodb-monitoring ./helm-charts/mongodb-monitoring \
  --set global.namespace=observability \
  --set global.region=$AWS_REGION

# 보안 강화 설정으로 설치
helm install mongodb-monitoring ./helm-charts/mongodb-monitoring \
  -f ./helm-charts/mongodb-monitoring/values-secure.yaml \
  --set global.region=$AWS_REGION
```

## Helm 차트 설정 커스터마이징

### 동적 값을 사용한 통합 차트 설정 예시
```yaml
# helm-charts/db-monitoring/values.yaml (동적 값 템플릿)
global:
  namespace: observability
  region: "{{ .Values.aws.region | default \"us-east-1\" }}"
  clusterName: "{{ .Values.aws.clusterName | default \"\" }}"
  accountId: "{{ .Values.aws.accountId | default \"\" }}"
  rbac:
    create: true

# AWS 환경별 설정 (배포 시 외부에서 주입)
aws:
  region: ""           # --set aws.region=$AWS_REGION
  accountId: ""        # --set aws.accountId=$ACCOUNT_ID
  clusterName: ""      # --set aws.clusterName=$CLUSTER_NAME

# Amazon Managed Prometheus configuration (동적 생성)
amp:
  workspaceId: "{{ .Values.aws.amp.workspaceId | default \"\" }}"
  endpoint: "{{ .Values.aws.amp.endpoint | default (printf \"https://aps-workspaces.%s.amazonaws.com/workspaces/%s/api/v1/remote_write\" .Values.aws.region .Values.aws.amp.workspaceId) }}"
  region: "{{ .Values.aws.region | default \"us-east-1\" }}"

# ADOT Collector configuration (동적 IAM 역할)
adot-collector:
  serviceAccount:
    create: true
    name: adot-collector
    annotations:
      eks.amazonaws.com/role-arn: "{{ .Values.aws.iam.adotRoleArn | default (printf \"arn:aws:iam::%s:role/adot-collector-role\" .Values.aws.accountId) }}"

# MongoDB Exporter configuration (동적 연결 정보)
mongodb-exporter:
  mongodb:
    uri: "mongodb://{{ .Values.databases.mongodb.instances[0].username | default \"test\" }}:{{ .Values.databases.mongodb.instances[0].password | default \"test\" }}@{{ .Values.databases.mongodb.instances[0].host | default \"test-mongodb\" }}.{{ .Values.global.namespace | default \"observability\" }}.svc.cluster.local:{{ .Values.databases.mongodb.instances[0].port | default 27017 }}/{{ .Values.databases.mongodb.instances[0].database | default \"admin\" }}"
    username: "{{ .Values.databases.mongodb.instances[0].username | default \"test\" }}"
    password: "{{ .Values.databases.mongodb.instances[0].password | default \"test\" }}"
    authDatabase: "{{ .Values.databases.mongodb.instances[0].database | default \"admin\" }}"
```

### 환경별 설정 파일 생성
```bash
# 개발 환경용 설정 파일 생성
cat > values-dev-custom.yaml << EOF
global:
  namespace: observability-dev
  region: us-west-2

databases:
  mongodb:
    enabled: true
    instances:
      - name: dev-mongodb
        host: dev-mongodb
        username: dev_user
        password: dev_password
EOF

# 프로덕션 환경용 설정 파일 생성
cat > values-prod-custom.yaml << EOF
global:
  namespace: observability-prod
  region: us-east-1

databases:
  mongodb:
    enabled: true
    instances:
      - name: prod-mongodb
        host: prod-mongodb
        username: prod_user
        password: prod_password
EOF
```

### 오버라이드 파일을 사용한 배포
```bash
# 개발 환경 배포
helm install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  -f values-dev-custom.yaml

# 프로덕션 환경 배포
helm install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  -f values-prod-custom.yaml

# 스테이징 환경 배포 (환경 변수 + 오버라이드 조합)
helm install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=staging-cluster \
  --set databases.mongodb.instances[0].host=staging-mongodb
```

## 대시보드 및 데이터소스 설정

### AMP 데이터소스 설정 (동적 값 사용) 

#### 자동 생성 방법 (권장)
```bash
# 환경 변수 설정 후 자동 생성
export AWS_REGION=us-east-1
export AMP_WORKSPACE_ID=ws-your-workspace-id

# AMP 데이터소스 설정 자동 생성
./scripts/generate-amp-datasource.sh
```

#### 수동 설정 방법
1. `amp-datasource-fixed.json` 파일 확인 (동적 값 템플릿)
2. 환경 변수 치환하여 실제 설정 파일 생성:
```bash
# 환경 변수 설정
export AWS_REGION=us-east-1
export AMP_WORKSPACE_ID=ws-c4d2c705-3a5c-436c-87b7-70a0e5549559

# 동적 값으로 실제 설정 파일 생성
envsubst < amp-datasource-fixed.json > amp-datasource-current.json
```

#### AMG에서 데이터소스 추가
1. Amazon Managed Grafana 콘솔에 접속
2. Configuration → Data sources → Add data source 선택
3. Prometheus 선택
4. 생성된 `amp-datasource-current.json` 내용을 복사하여 설정:
   - **Name**: Amazon Managed Prometheus
   - **URL**: `https://aps-workspaces.{region}.amazonaws.com/workspaces/{workspace-id}/`
   - **Access**: Server (default)
   - **Auth**: AWS SigV4 auth 활성화
   - **Default Region**: 해당 AWS 리전
   - **Auth Type**: Default

### Grafana 대시보드 가져오기
1. Amazon Managed Grafana 콘솔에 접속
2. 대시보드 → Import 선택
3. `dashboards/mongodb-dashboard.json` (MongoDB 대시보드) 파일을 업로드

## 고급 사용법

### 차트 관리 (동적 값 사용)
```bash
# 통합 차트 업데이트 - 환경 변수 사용
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID

# MongoDB Percona Operator 차트 업데이트
helm upgrade mongodb-monitoring ./helm-charts/mongodb-monitoring \
  --set global.region=$AWS_REGION \
  --set global.namespace=observability

# 특정 서브차트만 활성화/비활성화 - 동적 값 사용
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set databases.mongodb.enabled=true \
  --set databases.mongodb.instances[0].host=$MONGODB_HOST \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD

# 차트 제거
helm uninstall db-monitoring
helm uninstall mongodb-monitoring
```

### 템플릿 검증 (동적 값 포함)
```bash
# 의존성 차트 업데이트
helm dependency update ./helm-charts/db-monitoring

# 차트 템플릿 확인 (클러스터 연결 없이) - 동적 값 적용
helm template db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID

# MongoDB Percona Operator 템플릿 확인
helm template mongodb-monitoring ./helm-charts/mongodb-monitoring \
  --set global.region=$AWS_REGION

# 설치 전 dry-run (클러스터 연결 필요) - 동적 값 적용
helm install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --dry-run

# MongoDB Percona Operator dry-run
helm install mongodb-monitoring ./helm-charts/mongodb-monitoring \
  --set global.region=$AWS_REGION \
  --dry-run
```

### 환경별 배포 스크립트 생성
```bash
# 개발 환경 배포 스크립트
cat > deploy-dev.sh << 'EOF'
#!/bin/bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=dev-cluster
export AMP_WORKSPACE_ID=ws-dev-workspace-id
export MONGODB_HOST=dev-mongodb
export MONGODB_USERNAME=dev_user
export MONGODB_PASSWORD=dev_password

helm upgrade --install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --set databases.mongodb.instances[0].host=$MONGODB_HOST \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD \
  --namespace observability
EOF

# 스테이징 환경 배포 스크립트
cat > deploy-staging.sh << 'EOF'
#!/bin/bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=staging-cluster
export AMP_WORKSPACE_ID=ws-staging-workspace-id
export MONGODB_HOST=staging-mongodb
export MONGODB_USERNAME=staging_user
export MONGODB_PASSWORD=staging_password

helm upgrade --install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --set databases.mongodb.instances[0].host=$MONGODB_HOST \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD \
  --namespace observability
EOF

# 프로덕션 환경 배포 스크립트
cat > deploy-prod.sh << 'EOF'
#!/bin/bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=prod-cluster
export AMP_WORKSPACE_ID=ws-prod-workspace-id
export MONGODB_HOST=prod-mongodb
export MONGODB_USERNAME=prod_user
export MONGODB_PASSWORD=prod_password

helm upgrade --install db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set aws.amp.workspaceId=$AMP_WORKSPACE_ID \
  --set databases.mongodb.instances[0].host=$MONGODB_HOST \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD \
  --namespace observability
EOF

# 스크립트 실행 권한 부여
chmod +x deploy-*.sh
```

### 다중 환경 관리
```bash
# 환경별 네임스페이스 분리
helm install db-monitoring-dev ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set global.namespace=observability-dev \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set databases.mongodb.instances[0].host=dev-mongodb \
  --namespace observability-dev \
  --create-namespace

helm install db-monitoring-prod ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set global.namespace=observability-prod \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.clusterName=$CLUSTER_NAME \
  --set databases.mongodb.instances[0].host=prod-mongodb \
  --namespace observability-prod \
  --create-namespace
```

## 모니터링 메트릭

### MongoDB 메트릭 
- 문서 작업 통계, 연결 수
- 복제 세트 상태, 샤드 밸런싱
- 인덱스 성능, 메모리 사용률
- 컬렉션별 통계, 쿼리 성능
- 락 정보, 백그라운드 작업

## 보안 설정

### MongoDB 인증 설정 (동적 값 사용)
```bash
# MongoDB Exporter에서 인증 사용 - 환경 변수 활용
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set databases.mongodb.instances[0].username=$MONGODB_USERNAME \
  --set databases.mongodb.instances[0].password=$MONGODB_PASSWORD \
  --set databases.mongodb.instances[0].authDatabase=$MONGODB_DATABASE

# SSL/TLS 활성화 - 동적 값 사용
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set mongodb-exporter.ssl.enabled=true \
  --set mongodb-exporter.ssl.insecureSkipVerify=false
```

### 보안 강화된 환경 변수 설정
```bash
# AWS Secrets Manager에서 민감한 정보 가져오기
export MONGODB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id mongodb-monitoring-credentials \
  --region us-east-1 \
  --query SecretString --output text | jq -r .password)

export MONGODB_USERNAME=$(aws secretsmanager get-secret-value \
  --secret-id mongodb-monitoring-credentials \
  --region us-east-1 \
  --query SecretString --output text | jq -r .username)

# Parameter Store에서 설정 가져오기
export AMP_WORKSPACE_ID=$(aws ssm get-parameter \
  --name "/monitoring/amp/workspace-id" \
  --region us-east-1 \
  --query Parameter.Value --output text)

export ADOT_ROLE_ARN=$(aws ssm get-parameter \
  --name "/monitoring/iam/adot-role-arn" \
  --region us-east-1 \
  --query Parameter.Value --output text)
```

### MongoDB X.509 인증 설정 (Percona Operator) - 동적 값 사용
```bash
# 인증서 생성 (환경별 설정)
cd reference-configs
export CERT_DOMAIN="${CLUSTER_NAME}.${AWS_REGION}.compute.internal"
./generate-mongodb-certificates.sh $CERT_DOMAIN

# X.509 인증이 활성화된 MongoDB 클러스터 배포 - 동적 값 사용
helm install mongodb-monitoring ./helm-charts/mongodb-monitoring \
  --set global.region=$AWS_REGION \
  --set global.namespace=observability \
  --set mongodb.auth.enabled=true \
  --set mongodb.auth.type=x509 \
  --set mongodb.tls.enabled=true \
  --set mongodb.cluster.name="${CLUSTER_NAME}-mongodb"
```

### IAM 역할 설정 (동적 값 사용)
```bash
# ADOT Collector용 IAM 역할 생성 및 연결 - 동적 값 사용
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set aws.iam.adotRoleArn=$ADOT_ROLE_ARN \
  --set adot-collector.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ADOT_ROLE_ARN

# 환경별 IAM 역할 자동 생성
export ADOT_ROLE_NAME="adot-collector-role-${CLUSTER_NAME}"
export ADOT_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADOT_ROLE_NAME}"

# IAM 역할 존재 확인 및 생성
if ! aws iam get-role --role-name $ADOT_ROLE_NAME --region us-east-1 2>/dev/null; then
  echo "Creating IAM role: $ADOT_ROLE_NAME"
  # IAM 역할 생성 로직 추가
fi
```

### Kubernetes Secrets 관리 (동적 값 사용)
```bash
# MongoDB 인증 정보를 Kubernetes Secret으로 생성
kubectl create secret generic mongodb-credentials \
  --from-literal=username=$MONGODB_USERNAME \
  --from-literal=password=$MONGODB_PASSWORD \
  --from-literal=database=$MONGODB_DATABASE \
  --namespace observability

# Secret을 사용하는 Helm 배포
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set mongodb-exporter.existingSecret=mongodb-credentials

# TLS 인증서 Secret 생성 (환경별)
kubectl create secret tls mongodb-tls-cert \
  --cert=certs/${CLUSTER_NAME}-mongodb.crt \
  --key=certs/${CLUSTER_NAME}-mongodb.key \
  --namespace observability
```

### 네트워크 보안 설정
```bash
# Network Policy 활성화 - 동적 값 사용
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set security.networkPolicy.enabled=true \
  --set security.networkPolicy.ingress.enabled=true \
  --set security.networkPolicy.egress.enabled=true

# Pod Security Policy 활성화
helm upgrade db-monitoring ./helm-charts/db-monitoring \
  -f ./helm-charts/db-monitoring/values.yaml \
  --set aws.region=$AWS_REGION \
  --set aws.accountId=$ACCOUNT_ID \
  --set security.podSecurityPolicy.enabled=true
```

## 알림 설정

Amazon Managed Grafana에서 다음 알림을 설정할 수 있습니다:
- 데이터베이스 연결 실패
- 높은 CPU/메모리 사용률
- 슬로우 쿼리 임계값 초과
- 복제 지연 발생
- 캐시 메모리 부족
- MongoDB 샤드 불균형
- MongoDB 인덱스 성능 저하

## 문제 해결

### 일반적인 문제들

#### 1. Helm 차트 의존성 오류
```bash
# 의존성 업데이트
helm dependency update ./helm-charts/db-monitoring
helm dependency update ./helm-charts/mongodb-monitoring
```

#### 2. 템플릿 구문 오류
```bash
# 템플릿 검증 (클러스터 연결 없이)
helm template db-monitoring ./helm-charts/db-monitoring --debug
```

#### 3. ADOT Collector 또는 MongoDB Exporter CrashLoopBackOff
이 문제는 values 파일에서 Helm 템플릿 함수가 중첩 사용되어 발생합니다.

**해결 방법:**
```bash
# 1. values 파일에서 템플릿 함수 제거
# 2. 모든 값을 --set 옵션으로 명시적 설정
# 3. 또는 간단한 values 파일 사용

# 예시: 간단한 배포
helm upgrade --install db-monitoring ./helm-charts/db-monitoring \
  --set aws.region=ap-northeast-2 \
  --set aws.accountId=123456789012 \
  --set aws.clusterName=your-cluster-name \
  --set aws.amp.workspaceId=ws-your-workspace-id \
  --set aws.amp.endpoint=https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/ws-your-workspace-id/api/v1/remote_write \
  --set adot-collector.amp.endpoint=https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/ws-your-workspace-id/api/v1/remote_write \
  --set adot-collector.amp.region=ap-northeast-2 \
  --set databases.mongodb.instances[0].host=test-mongodb \
  --set databases.mongodb.instances[0].username=test \
  --set databases.mongodb.instances[0].password=test \
  --namespace observability
```

#### 4. MongoDB Percona Operator 차트 오류
```bash
# Percona 저장소 업데이트
helm repo update percona

# 사용 가능한 차트 확인
helm search repo percona
```

## 추가 문서

- [CLIENT-CONNECTION-GUIDE.md](CLIENT-CONNECTION-GUIDE.md): 데이터베이스 클라이언트 연결 가이드
- [PROJECT-STRUCTURE.md](PROJECT-STRUCTURE.md): 프로젝트 구조 상세 설명
- `reference-configs/`: MongoDB 고급 설정 참고 파일들
- `helm-charts/db-monitoring/charts/`: 각 서브차트별 상세 설정
- `helm-charts/mongodb-monitoring/`: MongoDB Percona Operator 차트 상세 설정
- `scripts/`: 배포 자동화 스크립트들


### 환경별 설정 지원
```bash
# 개발 환경 예시
export AWS_REGION=us-east-1
export CLUSTER_NAME=dev-cluster
export MONGODB_HOST=dev-mongodb

# 프로덕션 환경 예시  
export AWS_REGION=us-east-1
export CLUSTER_NAME=prod-cluster
export MONGODB_HOST=prod-mongodb
```
