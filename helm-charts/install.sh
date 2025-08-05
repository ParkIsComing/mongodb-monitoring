#!/bin/bash

# MongoDB Monitoring Helm Chart 설치 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 변수 설정
CHART_NAME="mongodb-monitoring"
NAMESPACE="mongodb-monitoring"
CHART_DIR="./mongodb-monitoring"

# 사전 요구사항 확인
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."
    
    # kubectl 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되지 않았습니다."
        exit 1
    fi
    
    # helm 확인
    if ! command -v helm &> /dev/null; then
        log_error "helm이 설치되지 않았습니다."
        exit 1
    fi
    
    # 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다."
        exit 1
    fi
    
    log_success "사전 요구사항 확인 완료"
}

# Helm Chart 설치
install_chart() {
    log_info "MongoDB Monitoring Helm Chart 설치 시작..."
    
    # Chart 디렉토리 확인
    if [ ! -d "$CHART_DIR" ]; then
        log_error "Chart 디렉토리를 찾을 수 없습니다: $CHART_DIR"
        exit 1
    fi
    
    cd "$CHART_DIR"
    
    # 의존성 업데이트
    log_info "Helm 의존성 업데이트 중..."
    helm dependency update
    
    # Chart 설치
    log_info "Chart 설치 중..."
    helm install "$CHART_NAME" . \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --values values.yaml \
        --timeout 10m0s
    
    if [ $? -eq 0 ]; then
        log_success "Chart 설치 완료"
    else
        log_error "Chart 설치 실패"
        exit 1
    fi
    
    cd ..
}

# 설치 상태 확인
check_installation() {
    log_info "설치 상태 확인 중..."
    
    # Helm 릴리스 상태 확인
    helm status "$CHART_NAME" -n "$NAMESPACE"
    
    # 파드 상태 확인
    log_info "MongoDB 파드 상태:"
    kubectl get pods -n percona-mongodb
    
    log_info "모니터링 파드 상태:"
    kubectl get pods -n observability
    
    # 서비스 확인
    log_info "서비스 상태:"
    kubectl get svc -n percona-mongodb
    kubectl get svc -n observability
    
    # MongoDB 클러스터 상태 확인
    log_info "MongoDB 클러스터 상태:"
    kubectl get psmdb -n percona-mongodb
}

# 메인 실행
main() {
    echo "=================================================="
    echo "MongoDB Monitoring Helm Chart 설치 스크립트"
    echo "=================================================="
    
    check_prerequisites
    install_chart
    
    log_info "설치 완료까지 대기 중... (최대 5분)"
    sleep 30
    
    check_installation
    
    echo "=================================================="
    log_success "MongoDB Monitoring 환경 설치 완료!"
    echo "=================================================="
    
    echo ""
    echo "다음 단계:"
    echo "1. MongoDB 클러스터 상태 확인: kubectl get psmdb -n percona-mongodb"
    echo "2. 모니터링 메트릭 확인: kubectl get pods -n observability"
    echo "3. Grafana에서 대시보드 import"
    echo ""
}

# 스크립트 실행
main "$@"
