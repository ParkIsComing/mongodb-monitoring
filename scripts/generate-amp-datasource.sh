#!/bin/bash

# 🎯 AMP 데이터소스 설정 동적 생성 스크립트
# Amazon Managed Grafana에서 사용할 AMP 데이터소스 설정을 환경 변수 기반으로 생성

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🎯 AMP 데이터소스 설정 동적 생성 시작${NC}"

# 필수 환경 변수 확인
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${AWS_REGION}" ]]; then
        missing_vars+=("AWS_REGION")
    fi
    
    if [[ -z "${AMP_WORKSPACE_ID}" ]]; then
        missing_vars+=("AMP_WORKSPACE_ID")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo -e "${RED}❌ 다음 환경 변수가 설정되지 않았습니다:${NC}"
        for var in "${missing_vars[@]}"; do
            echo -e "${RED}   - $var${NC}"
        done
        echo ""
        echo -e "${YELLOW}💡 환경 변수 설정 예시:${NC}"
        echo "export AWS_REGION=us-east-1"
        echo "export AMP_WORKSPACE_ID=ws-your-workspace-id"
        echo ""
        echo -e "${YELLOW}💡 또는 자동으로 가져오기:${NC}"
        echo "export AWS_REGION=\$(aws configure get region)"
        echo "export AMP_WORKSPACE_ID=\$(aws amp list-workspaces --query 'workspaces[0].workspaceId' --output text)"
        exit 1
    fi
}

# 환경 변수 자동 설정 (값이 없는 경우)
setup_environment_vars() {
    echo -e "${BLUE}📋 환경 변수 확인 및 설정${NC}"
    
    # AWS_REGION 자동 설정
    if [[ -z "${AWS_REGION}" ]]; then
        echo -e "${YELLOW}⚠️  AWS_REGION이 설정되지 않음. AWS CLI 설정에서 가져오는 중...${NC}"
        export AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            echo -e "${RED}❌ AWS CLI에서 기본 리전을 찾을 수 없습니다. 수동으로 설정해주세요.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ AWS_REGION 자동 설정: ${AWS_REGION}${NC}"
    fi
    
    # AMP_WORKSPACE_ID 자동 설정
    if [[ -z "${AMP_WORKSPACE_ID}" ]]; then
        echo -e "${YELLOW}⚠️  AMP_WORKSPACE_ID가 설정되지 않음. AWS에서 가져오는 중...${NC}"
        export AMP_WORKSPACE_ID=$(aws amp list-workspaces --region ${AWS_REGION} --query 'workspaces[0].workspaceId' --output text 2>/dev/null || echo "")
        if [[ -z "${AMP_WORKSPACE_ID}" || "${AMP_WORKSPACE_ID}" == "None" ]]; then
            echo -e "${RED}❌ AMP 워크스페이스를 찾을 수 없습니다. 수동으로 설정해주세요.${NC}"
            echo -e "${YELLOW}💡 AMP 워크스페이스 목록 확인:${NC}"
            echo "aws amp list-workspaces --region ${AWS_REGION}"
            exit 1
        fi
        echo -e "${GREEN}✅ AMP_WORKSPACE_ID 자동 설정: ${AMP_WORKSPACE_ID}${NC}"
    fi
    
    echo -e "${GREEN}✅ 환경 변수 설정 완료${NC}"
    echo "   - AWS_REGION: ${AWS_REGION}"
    echo "   - AMP_WORKSPACE_ID: ${AMP_WORKSPACE_ID}"
    echo ""
}

# AMP 데이터소스 설정 생성
generate_datasource_config() {
    echo -e "${BLUE}🔧 AMP 데이터소스 설정 생성 중...${NC}"
    
    local output_file="amp-datasource-current.json"
    local template_file="amp-datasource-fixed.json"
    
    # 템플릿 파일 존재 확인
    if [[ ! -f "${template_file}" ]]; then
        echo -e "${RED}❌ 템플릿 파일을 찾을 수 없습니다: ${template_file}${NC}"
        exit 1
    fi
    
    # envsubst를 사용하여 환경 변수 치환
    envsubst < "${template_file}" > "${output_file}"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ AMP 데이터소스 설정 생성 완료: ${output_file}${NC}"
        echo ""
        echo -e "${BLUE}📄 생성된 설정 내용:${NC}"
        cat "${output_file}" | jq '.'
        echo ""
    else
        echo -e "${RED}❌ AMP 데이터소스 설정 생성 실패${NC}"
        exit 1
    fi
}

# AMG 워크스페이스 정보 확인
check_amg_workspace() {
    echo -e "${BLUE}🔍 Amazon Managed Grafana 워크스페이스 확인 중...${NC}"
    
    local amg_workspaces=$(aws grafana list-workspaces --region ${AWS_REGION} --query 'workspaces[].{Id:id,Name:name,Status:status}' --output table 2>/dev/null || echo "")
    
    if [[ -n "${amg_workspaces}" && "${amg_workspaces}" != "None" ]]; then
        echo -e "${GREEN}✅ AMG 워크스페이스 발견:${NC}"
        echo "${amg_workspaces}"
        echo ""
        echo -e "${YELLOW}💡 AMG 콘솔에서 데이터소스를 추가하려면:${NC}"
        echo "1. AMG 콘솔 접속"
        echo "2. Configuration > Data sources > Add data source"
        echo "3. Prometheus 선택"
        echo "4. 생성된 amp-datasource-current.json 내용을 복사하여 설정"
    else
        echo -e "${YELLOW}⚠️  AMG 워크스페이스를 찾을 수 없습니다.${NC}"
        echo -e "${YELLOW}💡 AMG 워크스페이스를 먼저 생성해주세요.${NC}"
    fi
    echo ""
}

# 사용법 출력
print_usage() {
    echo -e "${BLUE}📖 사용법:${NC}"
    echo ""
    echo -e "${YELLOW}1. 환경 변수 설정:${NC}"
    echo "   export AWS_REGION=us-east-1"
    echo "   export AMP_WORKSPACE_ID=ws-your-workspace-id"
    echo ""
    echo -e "${YELLOW}2. 스크립트 실행:${NC}"
    echo "   ./scripts/generate-amp-datasource.sh"
    echo ""
    echo -e "${YELLOW}3. 생성된 파일 사용:${NC}"
    echo "   - amp-datasource-current.json 파일이 생성됩니다"
    echo "   - AMG 콘솔에서 이 설정을 사용하여 데이터소스를 추가하세요"
    echo ""
}

# 메인 실행
main() {
    # 환경 변수 자동 설정
    setup_environment_vars
    
    # 필수 환경 변수 확인
    check_required_vars
    
    # AMP 데이터소스 설정 생성
    generate_datasource_config
    
    # AMG 워크스페이스 확인
    check_amg_workspace
    
    # 사용법 출력
    print_usage
    
    echo -e "${GREEN}🎉 AMP 데이터소스 설정 생성 완료!${NC}"
}

# 스크립트 실행
main "$@"
