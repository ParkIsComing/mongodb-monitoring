#!/bin/bash

# AWS 리소스 자동 정리 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
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

# 환경 변수 설정
WORKSHOP_NAME="${WORKSHOP_NAME:-unified-db-monitoring}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-unified-db-monitoring-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log_info "AWS 리소스 정리 시작..."
echo "Workshop Name: $WORKSHOP_NAME"
echo "AWS Region: $AWS_REGION"
echo ""

# 1. Helm 릴리스 정리
cleanup_helm_releases() {
    log_info "Helm 릴리스 정리 중..."
    
    # 현재 릴리스 확인
    if helm list --all-namespaces | grep -q "db-monitoring\|mongodb-monitoring"; then
        log_info "발견된 Helm 릴리스들을 제거합니다..."
        
        # DB 모니터링 스택 제거
        if helm list --all-namespaces | grep -q "db-monitoring"; then
            log_info "db-monitoring 릴리스 제거 중..."
            helm uninstall db-monitoring --namespace observability || true
        fi
        
        # MongoDB 모니터링 스택 제거
        if helm list --all-namespaces | grep -q "mongodb-monitoring"; then
            log_info "mongodb-monitoring 릴리스 제거 중..."
            helm uninstall mongodb-monitoring --namespace observability || true
        fi
        
        log_success "Helm 릴리스 정리 완료"
    else
        log_info "정리할 Helm 릴리스가 없습니다."
    fi
}

# 2. Kubernetes 리소스 정리
cleanup_kubernetes_resources() {
    log_info "Kubernetes 리소스 정리 중..."
    
    # observability 네임스페이스 정리
    if kubectl get namespace observability 2>/dev/null; then
        log_info "observability 네임스페이스 제거 중..."
        kubectl delete namespace observability --timeout=300s || true
    fi
    
    # 남은 모니터링 관련 리소스 확인
    log_info "남은 모니터링 관련 리소스 확인 중..."
    kubectl get all --all-namespaces | grep -E "(mongodb|exporter|adot|prometheus)" || log_info "남은 모니터링 리소스가 없습니다."
    
    log_success "Kubernetes 리소스 정리 완료"
}

# 3. CloudFormation 스택 정리
cleanup_cloudformation_stacks() {
    log_info "CloudFormation 스택 정리 중..."
    
    # 스택 목록 확인
    local stacks=$(aws cloudformation list-stacks \
        --region $AWS_REGION \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '$WORKSHOP_NAME')].StackName" \
        --output text)
    
    if [ -z "$stacks" ]; then
        log_info "정리할 CloudFormation 스택이 없습니다."
        return
    fi
    
    log_info "발견된 스택들: $stacks"
    
    # 스택 삭제 (역순으로)
    local stack_order=(
        "${WORKSHOP_NAME}-monitoring"
        "${WORKSHOP_NAME}-eks"
        "${WORKSHOP_NAME}-database"
        "${WORKSHOP_NAME}-cache"
        "${WORKSHOP_NAME}-network"
    )
    
    for stack in "${stack_order[@]}"; do
        if echo "$stacks" | grep -q "$stack"; then
            log_info "$stack 스택 삭제 중..."
            aws cloudformation delete-stack --stack-name "$stack" --region $AWS_REGION
            
            # 삭제 완료 대기 (백그라운드에서)
            log_info "$stack 스택 삭제 대기 중... (백그라운드)"
            aws cloudformation wait stack-delete-complete --stack-name "$stack" --region $AWS_REGION &
        fi
    done
    
    # 모든 삭제 작업 완료 대기
    wait
    log_success "CloudFormation 스택 정리 완료"
}

# 4. AMP 워크스페이스 정리 (선택사항)
cleanup_amp_workspace() {
    log_warning "AMP 워크스페이스 정리는 수동으로 확인하세요."
    log_info "AMP 워크스페이스 목록:"
    aws amp list-workspaces --region $AWS_REGION --query 'workspaces[].{WorkspaceId:workspaceId,Alias:alias,Status:status}' --output table || true
    
    echo ""
    log_info "필요시 다음 명령으로 워크스페이스를 삭제하세요:"
    echo "aws amp delete-workspace --workspace-id WORKSPACE_ID --region $AWS_REGION"
}

# 5. AMG 워크스페이스 정리 (선택사항)
cleanup_amg_workspace() {
    log_warning "AMG 워크스페이스 정리는 수동으로 확인하세요."
    log_info "AMG 워크스페이스 목록:"
    aws grafana list-workspaces --region $AWS_REGION --query 'workspaces[].{Id:id,Name:name,Status:status}' --output table || true
    
    echo ""
    log_info "필요시 AWS 콘솔에서 AMG 워크스페이스를 삭제하세요."
}

# 6. IAM 역할 정리 (선택사항)
cleanup_iam_roles() {
    log_info "IAM 역할 확인 중..."
    
    local roles=$(aws iam list-roles --query "Roles[?contains(RoleName, 'adot-collector') || contains(RoleName, 'monitoring')].RoleName" --output text)
    
    if [ -n "$roles" ]; then
        log_warning "다음 IAM 역할들이 발견되었습니다:"
        echo "$roles"
        echo ""
        log_info "필요시 다음 명령으로 역할을 삭제하세요:"
        for role in $roles; do
            echo "aws iam delete-role --role-name $role"
        done
    else
        log_info "정리할 IAM 역할이 없습니다."
    fi
}

# 사용법 출력
usage() {
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  --all           모든 리소스 정리 (기본값)"
    echo "  --helm-only     Helm 릴리스만 정리"
    echo "  --k8s-only      Kubernetes 리소스만 정리"
    echo "  --cf-only       CloudFormation 스택만 정리"
    echo "  --dry-run       실제 삭제 없이 확인만"
    echo "  -h, --help      도움말 출력"
    echo ""
    echo "환경 변수:"
    echo "  WORKSHOP_NAME   워크샵 이름 (기본값: integrated-db-monitoring)"
    echo "  AWS_REGION      AWS 리전 (기본값: us-east-1)"
    echo ""
    echo "예시:"
    echo "  $0                    # 모든 리소스 정리"
    echo "  $0 --helm-only        # Helm 릴리스만 정리"
    echo "  $0 --dry-run          # 삭제 없이 확인만"
}

# 메인 실행
main() {
    local mode="all"
    local dry_run=false
    
    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                mode="all"
                shift
                ;;
            --helm-only)
                mode="helm"
                shift
                ;;
            --k8s-only)
                mode="k8s"
                shift
                ;;
            --cf-only)
                mode="cf"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [ "$dry_run" = true ]; then
        log_warning "DRY RUN 모드: 실제 삭제는 수행하지 않습니다."
        echo ""
    fi
    
    # 확인 메시지
    log_warning "다음 리소스들이 정리됩니다:"
    echo "  - Workshop Name: $WORKSHOP_NAME"
    echo "  - AWS Region: $AWS_REGION"
    echo "  - Mode: $mode"
    echo ""
    
    if [ "$dry_run" = false ]; then
        read -p "계속하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "작업이 취소되었습니다."
            exit 0
        fi
    fi
    
    # 리소스 정리 실행
    case $mode in
        "all")
            if [ "$dry_run" = false ]; then
                cleanup_helm_releases
                cleanup_kubernetes_resources
                cleanup_cloudformation_stacks
            fi
            cleanup_amp_workspace
            cleanup_amg_workspace
            cleanup_iam_roles
            ;;
        "helm")
            if [ "$dry_run" = false ]; then
                cleanup_helm_releases
            fi
            ;;
        "k8s")
            if [ "$dry_run" = false ]; then
                cleanup_kubernetes_resources
            fi
            ;;
        "cf")
            if [ "$dry_run" = false ]; then
                cleanup_cloudformation_stacks
            fi
            ;;
    esac
    
    if [ "$dry_run" = false ]; then
        log_success "리소스 정리가 완료되었습니다!"
    else
        log_info "DRY RUN 완료. 실제 정리를 원하면 --dry-run 옵션을 제거하고 다시 실행하세요."
    fi
}

# 스크립트 실행
main "$@"
