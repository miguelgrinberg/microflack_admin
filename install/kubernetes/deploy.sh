#!/bin/bash -e

# This script deploys MicroFlack to a kubernetes cluster.
# The deployed application will be available on port 30080.
# Note that the kubectl cli tool must be installed and in the path for this
# script to work.

KUBECTL=$(which kubectl || true)
if [[ "$KUBECTL" == "" ]]; then
    echo Please install and configure kubectl for your cluster.
    exit 1
fi

# there are two versions of the base64 utility, with slightly different behavior
BASE64_TEST1=$(base64 -b 0 <<<"test" 2> /dev/null || true)
BASE64_TEST2=$(base64 -w 0 <<<"test" 2>/dev/null || true)
if [[ "$BASE64_TEST1" == "dGVzdAo=" ]]; then
    BASE64="base64 -b 0"
elif [[ "$BASE64_TEST2" == "dGVzdAo=" ]]; then
    BASE64="base64 -w 0"
else
    echo "Unknown base64 utility, don't know how to configure it for single line output."
    exit 1
fi

# etcd
$KUBECTL create -f https://github.com/coreos/etcd/raw/master/hack/kubernetes-deploy/etcd.yml

# load balancer
$KUBECTL create -f lb.yaml

# app secrets
SECRET_KEY=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
JWT_SECRET_KEY=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
cat > app-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: app
type: Opaque
data:
  key: $(echo -n $SECRET_KEY | $BASE64)
  jwtkey: $(echo -n $JWT_SECRET_KEY | $BASE64)
EOF
$KUBECTL create -f ./app-secrets.yaml
rm app-secrets.yaml

# mysql passwords
MYSQL_ROOT_PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_USERS_PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_MESSAGES_PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_USERS_DB="mysql+pymysql://users:$MYSQL_USERS_PASSWORD@mysql:3306/users"
MYSQL_MESSAGES_DB="mysql+pymysql://messages:$MYSQL_MESSAGES_PASSWORD@mysql:3306/messages"
cat > mysql-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql
type: Opaque
data:
  root: $(echo -n $MYSQL_ROOT_PASSWORD | $BASE64)
  users: $(echo -n $MYSQL_USERS_DB | $BASE64)
  messages: $(echo -n $MYSQL_MESSAGES_DB | $BASE64)
EOF
$KUBECTL create -f ./mysql-secrets.yaml
rm mysql-secrets.yaml

# mysql
$KUBECTL create -f mysql-pv.yaml
$KUBECTL create -f mysql.yaml

# redis
$KUBECTL create -f redis.yaml

printf "Waiting for core services to be up..."
TOTAL=$($KUBECTL get pods --no-headers | wc -l | xargs)
while true; do
    UP=$($KUBECTL get pods --no-headers | grep Running | wc -l | xargs)
    printf "\rWaiting for core services to be up... $UP/$TOTAL"
    if [[ "$TOTAL" == "$UP" ]]; then
        break
    fi
    sleep 5
done
printf "\n"

MYSQL_POD=$($KUBECTL get pod -o custom-columns=name:.metadata.name | grep mysql)
LB_POD=$($KUBECTL get pod -o custom-columns=name:.metadata.name | grep lb)

# initialize mysql databases
$KUBECTL exec $MYSQL_POD -- mysqladmin --user=root --password="" password $MYSQL_ROOT_PASSWORD
$KUBECTL exec $MYSQL_POD -- mysql -e "CREATE DATABASE IF NOT EXISTS users;"
$KUBECTL exec $MYSQL_POD -- mysql -e "CREATE DATABASE IF NOT EXISTS messages;"
sleep 10
$KUBECTL exec $MYSQL_POD -- mysql -e "CREATE USER IF NOT EXISTS 'users'@'%' IDENTIFIED BY '$MYSQL_USERS_PASSWORD';GRANT ALL PRIVILEGES ON users.* TO 'users'@'%' IDENTIFIED BY '$MYSQL_USERS_PASSWORD';FLUSH PRIVILEGES;"
$KUBECTL exec $MYSQL_POD -- mysql -e "CREATE USER IF NOT EXISTS 'messages'@'%' IDENTIFIED BY '$MYSQL_MESSAGES_PASSWORD';GRANT ALL PRIVILEGES ON messages.* TO 'messages'@'%' IDENTIFIED BY '$MYSQL_MESSAGES_PASSWORD';FLUSH PRIVILEGES;"

# start application services
$KUBECTL create -f ui.yaml
$KUBECTL create -f users.yaml
$KUBECTL create -f tokens.yaml
$KUBECTL create -f messages.yaml
$KUBECTL create -f socketio.yaml

printf "Waiting for the remaining services to be up..."
TOTAL=$($KUBECTL get pods --no-headers | wc -l | xargs)
while true; do
    UP=$($KUBECTL get pods --no-headers | grep Running | wc -l | xargs)
    printf "\rWaiting for the remaining services to be up... $UP/$TOTAL"
    if [[ "$TOTAL" == "$UP" ]]; then
        break
    fi
    sleep 5
done
printf "\n"

# configure the load balancer to route to the proper services
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/ui/location -d value="/"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/ui/upstream/ui -d value="ui:5000"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/users/location -d value="/api/users"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/users/upstream/users -d value="users:5000"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/tokens/location -d value="/api/tokens"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/tokens/upstream/tokens -d value="tokens:5000"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/messages/location -d value="/api/messages"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/messages/upstream/messages -d value="messages:5000"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/socketio/location -d value="/socket.io"
$KUBECTL exec $LB_POD -- curl -f -s -o /dev/null -X PUT http://etcd0:2379/v2/keys/services/socketio/upstream/socketio -d value="socketio:5000"

echo "Done! Microflack is now deployed and can be accessed on port 30080 on your cluster."
