# MongoDB 인증 클라이언트 연결 가이드

AWS Security 권장사항에 따른 MongoDB 인증 설정 및 클라이언트 연결 방법

## 🔐 인증 메커니즘 개요

### 1. X.509 Certificate Authentication (우선 권장)
- **용도**: 공유 클러스터, 웹 서버 ↔ MongoDB 통신
- **장점**: 강력한 보안, 인증서 기반 신원 확인
- **단점**: 인증서 관리 복잡성

### 2. SCRAM-SHA-1 Authentication (보조 권장)
- **용도**: 사용자가 직접 MongoDB와 상호작용하는 경우
- **장점**: 사용자별 개별 자격 증명 관리 용이
- **단점**: 패스워드 기반 인증의 한계

## 🚀 클라이언트 연결 방법

### 1. X.509 인증서 기반 연결

#### 1.1 관리자 연결 (X.509)
```bash
# MongoDB Shell (mongosh) 연결
mongosh "mongodb://mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/?tls=true&tlsCAFile=/path/to/ca-cert.pem&tlsCertificateKeyFile=/path/to/admin-client.pem&authSource=\$external&authMechanism=MONGODB-X509"

# 또는 개별 옵션으로
mongosh --host mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017 \
        --tls \
        --tlsCAFile /path/to/ca-cert.pem \
        --tlsCertificateKeyFile /path/to/admin-client.pem \
        --authenticationDatabase '$external' \
        --authenticationMechanism MONGODB-X509
```

#### 1.2 애플리케이션 연결 (X.509)
```javascript
// Node.js 예제
const { MongoClient } = require('mongodb');

const uri = "mongodb://mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/?tls=true&authSource=%24external&authMechanism=MONGODB-X509";

const client = new MongoClient(uri, {
  tls: true,
  tlsCAFile: '/path/to/ca-cert.pem',
  tlsCertificateKeyFile: '/path/to/app-client.pem',
  authSource: '$external',
  authMechanism: 'MONGODB-X509'
});

async function connect() {
  try {
    await client.connect();
    console.log('✅ MongoDB X.509 연결 성공');
    
    const db = client.db('myapp');
    const collection = db.collection('users');
    
    // 데이터 조회 예제
    const users = await collection.find({}).toArray();
    console.log('사용자 목록:', users);
    
  } catch (error) {
    console.error('❌ 연결 실패:', error);
  } finally {
    await client.close();
  }
}

connect();
```

#### 1.3 Python 연결 (X.509)
```python
from pymongo import MongoClient
import ssl

# X.509 인증서 기반 연결
client = MongoClient(
    'mongodb://mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/',
    tls=True,
    tlsCAFile='/path/to/ca-cert.pem',
    tlsCertificateKeyFile='/path/to/app-client.pem',
    authSource='$external',
    authMechanism='MONGODB-X509'
)

try:
    # 연결 테스트
    client.admin.command('ping')
    print('✅ MongoDB X.509 연결 성공')
    
    # 데이터베이스 작업
    db = client.myapp
    collection = db.users
    
    # 문서 삽입
    result = collection.insert_one({'name': 'John', 'email': 'john@example.com'})
    print(f'문서 삽입 ID: {result.inserted_id}')
    
    # 문서 조회
    users = list(collection.find())
    print(f'사용자 수: {len(users)}')
    
except Exception as e:
    print(f'❌ 연결 실패: {e}')
finally:
    client.close()
```

### 2. SCRAM-SHA-1 인증 기반 연결

#### 2.1 관리자 연결 (SCRAM)
```bash
# MongoDB Shell 연결
mongosh "mongodb://databaseAdmin:PASSWORD@mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/admin?tls=true&tlsCAFile=/path/to/ca-cert.pem&authMechanism=SCRAM-SHA-1"

# 또는 개별 옵션으로
mongosh --host mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017 \
        --tls \
        --tlsCAFile /path/to/ca-cert.pem \
        --username databaseAdmin \
        --password \
        --authenticationDatabase admin \
        --authenticationMechanism SCRAM-SHA-1
```

#### 2.2 애플리케이션 연결 (SCRAM)
```javascript
// Node.js 예제
const { MongoClient } = require('mongodb');

const uri = "mongodb://appUser:PASSWORD@mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/myapp?tls=true&authMechanism=SCRAM-SHA-1";

const client = new MongoClient(uri, {
  tls: true,
  tlsCAFile: '/path/to/ca-cert.pem',
  authSource: 'admin',
  authMechanism: 'SCRAM-SHA-1'
});

async function connect() {
  try {
    await client.connect();
    console.log('✅ MongoDB SCRAM 연결 성공');
    
    const db = client.db('myapp');
    const collection = db.collection('products');
    
    // 데이터 작업
    await collection.insertOne({ name: 'Product 1', price: 100 });
    const products = await collection.find({}).toArray();
    console.log('제품 목록:', products);
    
  } catch (error) {
    console.error('❌ 연결 실패:', error);
  } finally {
    await client.close();
  }
}

connect();
```

#### 2.3 읽기 전용 연결 (SCRAM)
```python
from pymongo import MongoClient

# 읽기 전용 사용자 연결
client = MongoClient(
    'mongodb://readOnlyUser:PASSWORD@mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/',
    tls=True,
    tlsCAFile='/path/to/ca-cert.pem',
    authSource='admin',
    authMechanism='SCRAM-SHA-1'
)

try:
    # 연결 테스트
    client.admin.command('ping')
    print('✅ MongoDB SCRAM 읽기 전용 연결 성공')
    
    # 읽기 작업만 가능
    db = client.myapp
    collection = db.users
    
    users = list(collection.find())
    print(f'총 사용자 수: {len(users)}')
    
    # 쓰기 작업은 실패함
    try:
        collection.insert_one({'test': 'data'})
    except Exception as e:
        print(f'⚠️  예상된 쓰기 권한 오류: {e}')
    
except Exception as e:
    print(f'❌ 연결 실패: {e}')
finally:
    client.close()
```

## 🔧 연결 문자열 템플릿

### X.509 인증서 기반
```
mongodb://mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/?tls=true&tlsCAFile=/path/to/ca-cert.pem&tlsCertificateKeyFile=/path/to/client.pem&authSource=$external&authMechanism=MONGODB-X509
```

### SCRAM-SHA-1 기반
```
mongodb://username:password@mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017/database?tls=true&tlsCAFile=/path/to/ca-cert.pem&authMechanism=SCRAM-SHA-1
```

## 📋 사용자별 권한 매트릭스

| 사용자 | 인증 방식 | 권한 | 용도 |
|--------|-----------|------|------|
| admin (X.509) | MONGODB-X509 | 전체 관리 | 클러스터 관리 |
| databaseAdmin | SCRAM-SHA-1 | DB 관리 | 데이터베이스 관리 |
| clusterAdmin | SCRAM-SHA-1 | 클러스터 관리 | 클러스터 운영 |
| mongodb-app-user (X.509) | MONGODB-X509 | 앱 DB 읽기/쓰기 | 애플리케이션 |
| appUser | SCRAM-SHA-1 | 앱 DB 읽기/쓰기 | 애플리케이션 |
| mongodb-monitor (X.509) | MONGODB-X509 | 모니터링 | 메트릭 수집 |
| clusterMonitor | SCRAM-SHA-1 | 모니터링 | 메트릭 수집 |
| readOnlyUser | SCRAM-SHA-1 | 전체 읽기 | 분석/리포팅 |
| backupUser | SCRAM-SHA-1 | 백업/복원 | 백업 작업 |

## 🛡️ 보안 모범 사례

### 1. X.509 인증서 관리
- **인증서 보관**: 안전한 위치에 개인키 보관
- **권한 설정**: 인증서 파일 권한을 600으로 설정
- **만료 관리**: 인증서 만료일 추적 및 자동 갱신
- **폐기 관리**: 불필요한 인증서 즉시 폐기

### 2. SCRAM 패스워드 관리
- **강력한 패스워드**: 최소 32자 이상의 복잡한 패스워드
- **정기 변경**: 90일마다 패스워드 변경
- **개별 계정**: 사용자별 개별 계정 사용
- **최소 권한**: 필요한 최소 권한만 부여

### 3. 네트워크 보안
- **TLS 강제**: 모든 연결에 TLS 사용
- **방화벽**: 필요한 포트만 개방
- **VPN**: 가능한 경우 VPN을 통한 접근
- **IP 제한**: 허용된 IP에서만 접근

## 🔍 연결 문제 해결

### 1. 인증서 관련 오류
```bash
# 인증서 유효성 확인
openssl x509 -in client-cert.pem -text -noout

# 인증서와 키 매칭 확인
openssl x509 -noout -modulus -in client-cert.pem | openssl md5
openssl rsa -noout -modulus -in client-key.pem | openssl md5
```

### 2. 연결 테스트
```bash
# 기본 연결 테스트
mongosh --host mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017 \
        --tls \
        --tlsCAFile ca-cert.pem \
        --eval "db.adminCommand('ping')"

# 인증 테스트
mongosh --host mongodb-sharded-mongos.percona-mongodb.svc.cluster.local:27017 \
        --tls \
        --tlsCAFile ca-cert.pem \
        --tlsCertificateKeyFile admin-client.pem \
        --authenticationDatabase '$external' \
        --authenticationMechanism MONGODB-X509 \
        --eval "db.runCommand({connectionStatus: 1})"
```

### 3. 로그 확인
```bash
# MongoDB 로그 확인
kubectl logs -n percona-mongodb mongodb-sharded-mongos-0

# 인증 관련 로그 필터링
kubectl logs -n percona-mongodb mongodb-sharded-mongos-0 | grep -i auth
```

## 📞 지원 및 문의

- **MongoDB 공식 문서**: https://docs.mongodb.com/manual/core/authentication/
- **Percona 문서**: https://docs.percona.com/percona-operator-for-mongodb/
- **X.509 인증 가이드**: https://docs.mongodb.com/manual/tutorial/configure-x509-client-authentication/
- **SCRAM 인증 가이드**: https://docs.mongodb.com/manual/core/security-scram/
