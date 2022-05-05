#!/usr/bin/env bash

# This Script Generates Files Nessasary to Build MongoDB Cluster and Replica Sets

# Default Options
compose_version=3.3
node_version=latest

mongo_express_version=0.54.0
mongodb_version=5.0.5
mongodb_sh_version=1.1.8
mongodb_port=27017
mongo_express_port=8081
configdb=configdb
initdb=binlex
replicas=3
shards=2
routers=2
admin_user=admin
admin_pass=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)
username=binlex
password=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)

threads=4
thread_cycles=10
thread_sleep=500

brokers=4
rabbitmq_version=3.9
rabbitmq_cookie=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)
rabbitmq_port=5672
rabbitmq_http_port=15672

bldbs=1
bldb_version=1.1.1

bldecs=1
bldec_version=1.1.1

blapis=1
blapi_version=1.1.1
blapi_users=1
blapi_admins=1
blapi_http_port=8080
blapi_https_port=8443

bljupyters=1
bljupyter_port=8888
bljupyter_version=1.1.1
bljupyter_token=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)

minios=4
minio_version=RELEASE.2022-01-28T02-28-16Z
minio_api_port=9000
minio_console_port=9001
minio_root_user=admin
minio_root_password=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)

# prom/prometheus
prometheus_version=v2.33.0
prometheus_port=9090

DOCKER_UID=$(id -u):$(id -g)
CWD=$(pwd)

function help_menu(){
    printf "docker.sh - Binlex Production Docker Generator\n";
    printf "  -h\t\t--help\t\t\tHelp Menu\n";
    printf "  -mp\t\t--mongodb-port\t\tMongoDB Port\n";
    printf "  -mep\t\t--mongo-express-port\tMongo Express Port\n";
    printf "  -c\t\t--configdb\t\tMongoDB ConfigDB Name\n";
    printf "  -i\t\t--initdb\t\tMongoDB InitDB Name\n";
    printf "  -reps\t\t--replicas\t\tMongoDB Replica Count\n";
    printf "  -shrds\t--shards\t\tMongoDB Shard Count\n";
    printf "  -rtrs\t\t--routers\t\tMongoDB Routers Count\n";
    printf "  -au\t\t--admin-user\t\tMongoDB Admin User\n";
    printf "  -ap\t\t--admin-pass\t\tMongoDB Admin Password\n";
    printf "  -u\t\t--username\t\tMongoDB InitDB Username\n";
    printf "  -p\t\t--password\t\tMongoDB InitDB Password\n";
    printf "Author: @c3rb3ru5d3d53c\n";
}

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            help_menu
            exit 0
            ;;
        -mp|--mongodb-port)
            shift
            if test $# -gt 0; then
                mongodb_port=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -mep|--mongodb-express-port)
            shift
            if test $# -gt 0; then
                mongo_express_port=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -reps|--replicas)
            shift
            if test $# -gt 0; then
                replicas=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -shrds|--shards)
            shift
            if test $# -gt 0; then
                shards=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -rtrs|--routers)
            shift
            if test $# -gt 0; then
                routers=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -au|--admin-user)
            shift
            if test $# -gt 0; then
                admin_user=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -ap|--admin-pass)
            shift
            if test $# -gt 0; then
                admin_pass=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -u|--username)
            shift
            if test $# -gt 0; then
                username=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
        -p|--password)
            shift
            if test $# -gt 0; then
                password=$1
            else
                echo "[x] missing argument"
                exit 1
            fi
            ;;
    esac
    shift
done

function generate_alt_dns(){
    echo "[ v3_req ]";
    echo "subjectAltName = @alt_names";
    echo "[ alt_names ]";
    echo "IP.1 = 127.0.0.1";
    echo "DNS.2 = localhost";
    echo "DNS.3 = $1";
}

function generate_certificates(){
    mkdir -p config/
    # Create CA
    openssl req \
        -passout pass:${admin_pass} \
        -new -x509 \
        -days 365 \
        -extensions v3_ca \
        -keyout config/binlex-private-ca.pem \
        -out config/binlex-public-ca.pem \
        -subj "/CN=CA/OU=binlex";

    openssl x509 -outform der -in config/binlex-public-ca.pem -out config/binlex-public-ca.crt;

    # Create Client Certificate
    openssl req \
        -newkey rsa:4096 \
        -nodes \
        -out config/binlex-client.csr \
        -keyout config/binlex-client.key \
        -subj "/CN=binlex-client/OU=binlex-clients";

    # Sign Client Certificate
    openssl x509 \
        -passin pass:${admin_pass} \
        -sha256 -req \
        -days 365 \
        -in config/binlex-client.csr \
        -CA config/binlex-public-ca.pem \
        -CAkey config/binlex-private-ca.pem \
        -CAcreateserial \
        -out config/binlex-client.crt;

    cat config/binlex-client.crt config/binlex-client.key > config/binlex-client.pem;

    # Generate Certificates for Shards
    for i in $(seq 1 $shards); do
        for j in $(seq 1 $replicas); do
            generate_alt_dns mongodb-shard${i}-rep${j} > config/mongodb-shard${i}-rep${j}.ext;
            openssl req \
                -newkey rsa:4096 \
                -nodes \
                -out config/mongodb-shard${i}-rep${j}.csr \
                -keyout config/mongodb-shard${i}-rep${j}.key \
                -subj "/CN=mongodb-shard${i}-rep${j}/OU=binlex-mongodb";
            openssl x509 \
                -passin pass:${admin_pass} \
                -sha256 \
                -req \
                -days 365 \
                -in config/mongodb-shard${i}-rep${j}.csr \
                -CA config/binlex-public-ca.pem \
                -CAkey config/binlex-private-ca.pem \
                -CAcreateserial \
                -out config/mongodb-shard${i}-rep${j}.crt \
                -extensions v3_req \
                -extfile config/mongodb-shard${i}-rep${j}.ext;
            cat config/mongodb-shard${i}-rep${j}.crt config/mongodb-shard${i}-rep${j}.key > config/mongodb-shard${i}-rep${j}.pem;
        done
    done

    for i in $(seq 1 $replicas); do
        generate_alt_dns mongodb-config-rep${i} > config/mongodb-config-rep${i}.ext;
        openssl req \
            -newkey rsa:4096 \
            -nodes \
            -out config/mongodb-config-rep${i}.csr \
            -keyout config/mongodb-config-rep${i}.key \
            -subj "/CN=mongodb-config-rep${i}/OU=binlex-mongodb";
        openssl x509 \
            -passin pass:${admin_pass} \
            -sha256 \
            -req \
            -days 365 \
            -in config/mongodb-config-rep${i}.csr \
            -CA config/binlex-public-ca.pem \
            -CAkey config/binlex-private-ca.pem \
            -CAcreateserial \
            -out config/mongodb-config-rep${i}.crt \
            -extensions v3_req \
            -extfile config/mongodb-config-rep${i}.ext;
        cat config/mongodb-config-rep${i}.crt config/mongodb-config-rep${i}.key > config/mongodb-config-rep${i}.pem;
    done

    for i in $(seq 1 $routers); do
        generate_alt_dns mongodb-router${i} > config/mongodb-router${i}.ext;
        openssl req \
            -newkey rsa:4096 \
            -nodes \
            -out config/mongodb-router${i}.csr \
            -keyout config/mongodb-router${i}.key \
            -subj "/CN=mongodb-router${i}/OU=binlex-mongodb";
        openssl x509 \
            -passin pass:${admin_pass} \
            -sha256 \
            -req \
            -days 365 \
            -in config/mongodb-router${i}.csr \
            -CA config/binlex-public-ca.pem \
            -CAkey config/binlex-private-ca.pem \
            -CAcreateserial \
            -out config/mongodb-router${i}.crt \
            -extensions v3_req \
            -extfile config/mongodb-router${i}.ext;
        cat config/mongodb-router${i}.crt config/mongodb-router${i}.key > config/mongodb-router${i}.pem;
    done

    for i in $(seq 1 $brokers); do
        generate_alt_dns rabbitmq-broker${i} > config/rabbitmq-broker${i}.ext;
        openssl req \
            -newkey rsa:4096 \
            -nodes \
            -out config/rabbitmq-broker${i}.csr \
            -keyout config/rabbitmq-broker${i}.key \
            -subj "/CN=rabbitmq-broker${i}/OU=binlex-rabbitmq";
        openssl x509 \
            -passin pass:${admin_pass} \
            -sha256 \
            -req \
            -days 365 \
            -in config/rabbitmq-broker${i}.csr \
            -CA config/binlex-public-ca.pem \
            -CAkey config/binlex-private-ca.pem \
            -CAcreateserial \
            -out config/rabbitmq-broker${i}.crt \
            -extensions v3_req \
            -extfile config/rabbitmq-broker${i}.ext;
        cat config/rabbitmq-broker${i}.crt config/rabbitmq-broker${i}.key > config/rabbitmq-broker${i}.pem;
    done

    for i in $(seq 1 $blapis); do
        generate_alt_dns blapi${i} > config/blapi${i}.ext;
        openssl req \
            -newkey rsa:4096 \
            -nodes \
            -out config/blapi${i}.csr \
            -keyout config/blapi${i}.key \
            -subj "/CN=blapi${i}/OU=binlex-blapi";
        openssl x509 \
            -passin pass:${admin_pass} \
            -sha256 \
            -req \
            -days 365 \
            -in config/blapi${i}.csr \
            -CA config/binlex-public-ca.pem \
            -CAkey config/binlex-private-ca.pem \
            -CAcreateserial \
            -out config/blapi${i}.crt \
            -extensions v3_req \
            -extfile config/blapi${i}.ext;
        cat config/blapi${i}.crt config/blapi${i}.key > config/blapi${i}.pem;
    done

    for i in $(seq 1 $bljupyters); do
        generate_alt_dns bljupyter${i} > config/bljupyter${i}.ext;
        openssl req \
            -newkey rsa:4096 \
            -nodes \
            -out config/bljupyter${i}.csr \
            -keyout config/bljupyter${i}.key \
            -subj "/CN=bljupyter${i}/OU=binlex-bljupyter";
        openssl x509 \
            -passin pass:${admin_pass} \
            -sha256 \
            -req \
            -days 365 \
            -in config/bljupyter${i}.csr \
            -CA config/binlex-public-ca.pem \
            -CAkey config/binlex-private-ca.pem \
            -CAcreateserial \
            -out config/bljupyter${i}.crt \
            -extensions v3_req \
            -extfile config/bljupyter${i}.ext;
        cat config/bljupyter${i}.crt config/bljupyter${i}.key > config/bljupyter${i}.pem;
    done

    for i in $(seq 1 $minios); do
        generate_alt_dns minio${i} > config/minio${i}.ext;
        openssl req \
            -newkey rsa:4096 \
            -nodes \
            -out config/minio${i}.csr \
            -keyout config/minio${i}.key \
            -subj "/CN=minio${i}/OU=binlex-minio";
        openssl x509 \
            -passin pass:${admin_pass} \
            -sha256 \
            -req \
            -days 365 \
            -in config/minio${i}.csr \
            -CA config/binlex-public-ca.pem \
            -CAkey config/binlex-private-ca.pem \
            -CAcreateserial \
            -out config/minio${i}.crt \
            -extensions v3_req \
            -extfile config/minio${i}.ext;
        cat config/minio${i}.crt config/minio${i}.key > config/minio${i}.pem;
    done

}

generate_certificates

rm -rf scripts/
mkdir -p scripts/

if [ ! -f config/replica.key ]; then
    openssl rand -base64 346 > config/replica.key;
    chmod 600 config/replica.key
fi

function compose() {
    echo "version: '${compose_version}'"
    echo "";
    echo "services:";
    for j in $(seq 1 $shards); do
        for i in $(seq 1 $replicas); do
            echo "  mongodb-shard${j}-rep${i}:";
            echo "      hostname: mongodb-shard${j}-rep${i}";
            echo "      container_name: mongodb-shard${j}-rep${i}";
            echo "      image: mongo:${mongodb_version}";
            echo "      build:";
            echo "          context: docker/mongodb/";
            echo "          dockerfile: Dockerfile";
            echo "          args:";
            echo "              UID: `id -u`";
            echo "              GID: `id -g`";
            echo "      command: mongod --shardsvr --bind_ip_all --replSet shard${j} --port ${mongodb_port} --dbpath /data/db/ --keyFile /config/replica.key --tlsMode requireTLS --tlsCertificateKeyFile /config/mongodb-shard${j}-rep${i}.pem --tlsCAFile /config/binlex-public-ca.pem";
            echo "      volumes:";
            echo "          - ./config/:/config/";
            echo "          - ./data/mongodb-shard${j}-rep${i}/:/data/db/";
        done
    done
    for i in $(seq 1 $replicas); do
        echo "  mongodb-config-rep${i}:";
        echo "      hostname: mongodb-config-rep${i}";
        echo "      container_name: mongodb-config-rep${i}";
        echo "      image: mongo:${mongodb_version}";
        echo "      build:";
        echo "          context: docker/mongodb/";
        echo "          dockerfile: Dockerfile";
        echo "          args:";
        echo "              UID: `id -u`";
        echo "              GID: `id -g`";
        echo "      command: mongod --configsvr --bind_ip_all --replSet ${configdb} --port ${mongodb_port} --dbpath /data/db/ --keyFile /config/replica.key --tlsMode requireTLS --tlsCertificateKeyFile /config/mongodb-config-rep${i}.pem --tlsCAFile /config/binlex-public-ca.pem";
        echo "      volumes:";
        echo "          - ./config/:/config/";
        echo "          - ./data/mongodb-config-rep${i}/:/data/db/";
    done
    for i in $(seq 1 $routers); do
        echo "  mongodb-router${i}:";
        echo "      hostname: mongodb-router${i}";
        echo "      container_name: mongodb-router${i}";
        echo "      image: mongo:${mongodb_version}";
        echo "      build:";
        echo "          context: docker/mongodb/";
        echo "          dockerfile: Dockerfile";
        echo "          args:";
        echo "              UID: `id -u`";
        echo "              GID: `id -g`";
        echo -n "      command: mongos --keyFile /config/replica.key --bind_ip_all --port ${mongodb_port} --tlsMode requireTLS --tlsCertificateKeyFile /config/mongodb-router${i}.pem --tlsCAFile /config/binlex-public-ca.pem --configdb ";
        echo -n "\"${configdb}/";
        for j in $(seq 1 $replicas); do
            echo -n "mongodb-config-rep${j}:${mongodb_port},";
        done | sed 's/,$//'
        echo "\"";
        echo "      volumes:";
        echo "          - ./config/:/config/";
        echo "          - ./data/mongodb-router${i}/:/data/db/";
        echo "      ports:";
        echo "          - `expr ${mongodb_port} + ${i} - 1`:${mongodb_port}"
        echo "      depends_on:";
        for j in $(seq 1 $replicas); do
            echo "          - mongodb-config-rep${j}";
        done
    done

    for i in $(seq 1 $brokers); do
        echo "  rabbitmq-broker${i}:";
        echo "      hostname: rabbitmq-broker${i}";
        echo "      container_name: rabbitmq-broker${i}";
        echo "      image: rabbitmq:${rabbitmq_version}-management";
        echo "      build:";
        echo "          context: docker/rabbitmq/";
        echo "          dockerfile: Dockerfile";
        echo "          args:";
        echo "              UID: `id -u`";
        echo "              GID: `id -g`";
        echo "      environment:";
        echo "          RABBITMQ_ERLANG_COOKIE: \"${rabbitmq_cookie}\"";
        echo "          RABBITMQ_DEFAULT_USER: \"${admin_user}\"";
        echo "          RABBITMQ_DEFAULT_PASS: \"${admin_pass}\"";
        echo "          RABBITMQ_CONFIG_FILE: \"/config/rabbitmq-broker${i}.conf\"";
        echo "      ports:";
        echo "          - `expr ${rabbitmq_port} + ${i} - 1`:5672";
        echo "          - `expr ${rabbitmq_http_port} + ${i} - 1`:15672";
        echo "      volumes:";
        echo "          - ./data/rabbitmq-broker${i}/:/var/lib/rabbitmq/mnesia/";
        echo "          - ./config/:/config/";
    done

    rabbitmq_iter=1;
    mongodb_iter=1;
    for i in $(seq 1 $bldbs); do
        echo "  bldb${i}:";
        echo "      hostname: bldb${i}";
        echo "      container_name: bldb${i}";
        echo "      image: bldb:${bldb_version}";
        echo "      build:";
        echo "          context: .";
        echo "          dockerfile: docker/bldb/Dockerfile";
        echo "      volumes:";
        echo "          - ./config/bldb${i}.conf:/startup/bldb.conf";
        echo "          - ./config/:/config/";
        echo "      depends_on:";
        for j in $(seq 1 $brokers); do
            echo "          - rabbitmq-broker${j}";
        done
        if [ ${rabbitmq_iter} -eq $brokers ]; then
            rabbitmq_iter=1;
        else
            rabbitmq_iter=$((rabbitmq_iter+1));
        fi
        if [ ${mongodb_iter} -eq $routers ]; then
            mongodb_iter=1;
        else
            mongodb_iter=$((mongodb_iter+1));
        fi
    done

    rabbitmq_iter=1;
    mongodb_iter=1;
    minio_iter=1
    for i in $(seq 1 $bldecs); do
        echo "  bldec${i}:";
        echo "      hostname: bldec${i}";
        echo "      container_name: bldec${i}";
        echo "      image: bldec:${bldec_version}";
        echo "      build:";
        echo "          context: .";
        echo "          dockerfile: docker/bldec/Dockerfile";
        echo "      volumes:";
        echo "          - ./config/bldec${i}.conf:/startup/bldec.conf";
        echo "          - ./config/:/config/";
        echo "      depends_on:";
        for j in $(seq 1 $brokers); do
            echo "          - rabbitmq-broker${j}";
        done
        if [ ${rabbitmq_iter} -eq $brokers ]; then
            rabbitmq_iter=1;
        else
            rabbitmq_iter=$((rabbitmq_iter+1));
        fi
        if [ ${mongodb_iter} -eq $routers ]; then
            mongodb_iter=1;
        else
            mongodb_iter=$((mongodb_iter+1));
        fi
        if [ ${minio_iter} -eq $minios ]; then
            minio_iter=1;
        else
            minio_iter=$((minio_iter+1));
        fi
    done

    for i in $(seq 1 $blapis); do
        echo "  blapi${i}:";
        echo "      hostname: blapi${i}";
        echo "      container_name: blapi${i}";
        echo "      image: blapi:${blapi_version}";
        echo "      build:";
        echo "          context: .";
        echo "          dockerfile: docker/blapi/Dockerfile";
        echo "      ports:";
        echo "          - `expr ${blapi_http_port} + ${i} - 1`:${blapi_http_port}";
        echo "          - `expr ${blapi_https_port} + ${i} - 1`:${blapi_https_port}";
        echo "      volumes:";
        echo "          - ./config/blapi${i}_nginx.conf:/etc/nginx/conf.d/blapi.conf";
        echo "          - ./config/blapi${i}.conf:/startup/blapi.conf";
        echo "          - ./config/:/config/";
        echo "      depends_on:";
        for j in $(seq 1 $brokers); do
            echo "          - rabbitmq-broker${j}";
        done
        for j in $(seq 1 $routers); do
            echo "          - mongodb-router${j}";
        done
        for j in $(seq 1 $bldbs); do
            echo "          - bldb${j}";
        done
        for j in $(seq 1 $shards); do
            for i in $(seq 1 $replicas); do
                echo "  mongodb-shard${j}-rep${i}:";
	    done
        done
    done
    for i in $(seq 1 $bljupyters); do
        echo "  bljupyter${i}:";
        echo "      hostname: bljupyter${i}";
        echo "      container_name: bljupyter${i}";
        echo "      image: bljupyter:${bljupyter_version}";
        echo "      user: ${DOCKER_UID}";
        echo "      build:";
        echo "          context: .";
        echo "          dockerfile: docker/bljupyter/Dockerfile";
        echo "      environment:";
        echo "          - JUPYTER_TOKEN=${bljupyter_token}";
        echo "      ports:";
        echo "          - `expr ${bljupyter_port} + ${i} - 1`:8888";
        echo "      volumes:";
        echo "          - ./config/:/config/";
        echo "          - ./:/tf/notebooks";
    done
    minio_port_iter=1
    for i in $(seq 1 $minios); do
        echo "  minio${i}:";
        echo "      hostname: minio${i}";
        echo "      container_name: minio${i}";
        echo "      image: minio/minio:${minio_version}";
        echo "      environment:";
        echo "          - MINIO_ROOT_USER=${admin_user}";
        echo "          - MINIO_ROOT_PASSWORD=${admin_pass}";
        echo "          - MINIO_SERVER_URL=https://minio1:${minio_api_port}";
        echo "          - MINIO_PROMETHEUS_AUTH_TYPE=public";
        echo "          - MINIO_PROMETHEUS_URL=http://prometheus:${prometheus_port}";
        echo "      command: server https://minio{1...$minios}/data --address :${minio_api_port} --console-address :${minio_console_port}";
        echo "      ports:";
        echo "          - `expr ${minio_api_port} + ${minio_port_iter} - 1`:${minio_api_port}";
        echo "          - `expr ${minio_console_port} + ${minio_port_iter} - 1`:${minio_console_port}";
        echo "      volumes:";
        echo "      - ./config/binlex-public-ca.pem:/root/.minio/certs/CAs/public.crt";
        echo "      - ./config/minio${i}.crt:/root/.minio/certs/public.crt";
        echo "      - ./config/minio${i}.key:/root/.minio/certs/private.key";
        echo "      - ./config/:/config/";
        echo "      - ./data/minio${i}:/data/";
        minio_port_iter=$((minio_port_iter+2));
    done

    echo "  prometheus:";
    echo "      hostname: prometheus";
    echo "      container_name: prometheus";
    echo "      image: prom/prometheus:${prometheus_version}";
    echo "      ports:";
    echo "          - ${prometheus_port}:${prometheus_port}";
    echo "      volumes:";
    echo "          - ./config/prometheus.yml:/etc/prometheus/prometheus.yml";
    echo "          - ./config/:/config/";
}

compose > docker-compose.yml

function prometheus_config_init(){
    echo "scrape_configs:";
    echo "  - job_name: minio";
    echo "    scheme: https";
    echo "    metrics_path: /minio/prometheus/metrics";
    echo "    static_configs:";
    echo -n "      - targets: ["
    for i in $(seq 1 $minios); do
        echo -n "'minio${i}:${minio_api_port}',";
    done | sed 's/\,$//'
    echo "]";
    echo "    tls_config:";
    echo "      ca_file: /config/binlex-public-ca.pem";
}

function bldec_config_init(){
    echo "[bldec]";
    echo "threads = ${threads}";
    echo "thread_cycles = ${thread_cycles}";
    echo "thread_sleep = ${thread_sleep}";
    echo "[amqp]";
    echo "tls = yes";
    echo "traits_queue = bltraits";
    echo "decomp_queue = bldecomp";
    echo "user = ${admin_user}";
    echo "pass = ${admin_pass}";
    echo "ca = /config/binlex-public-ca.pem";
    echo "cert = /config/binlex-client.crt";
    echo "key = /config/binlex-client.key";
    echo "port = ${rabbitmq_port}";
    echo "host = $1";
    echo "[minio]";
    echo "tls = yes";
    echo "host = $2";
    echo "port = ${minio_api_port}";
    echo "user = ${admin_user}";
    echo "pass = ${admin_pass}";
    echo "ca = /config/binlex-public-ca.pem";
}

function bldb_config_init(){
    echo "[mongodb]";
    echo "db = binlex";
    echo "tls = yes";
    echo "ca = /config/binlex-public-ca.pem";
    echo "key = /config/binlex-client.pem";
    echo "url = mongodb://${admin_user}:${admin_pass}@$1:${mongodb_port}";
    echo "[amqp]";
    echo "tls = yes";
    echo "traits_queue = bltraits";
    echo "user = ${admin_user}";
    echo "pass = ${admin_pass}";
    echo "ca = /config/binlex-public-ca.pem";
    echo "cert = /config/binlex-client.crt";
    echo "key = /config/binlex-client.key";
    echo "port = ${rabbitmq_port}";
    echo "host = $2";
}

function blapi_config_init(){
    echo "[blapi]";
    echo "debug = no";
    echo "port = 5000";
    echo "host = 0.0.0.0";
    echo "user_keys = /config/blapi_user.keys";
    echo "admin_keys = /config/blapi_admin.keys";
    echo "[mongodb]";
    echo "db = binlex";
    echo "tls = yes";
    echo "ca = /config/binlex-public-ca.pem";
    echo "key = /config/binlex-client.pem";
    echo "url = mongodb://${admin_user}:${admin_pass}@$1:${mongodb_port}";
    echo "[amqp]";
    echo "tls = yes";
    echo "user = ${admin_user}";
    echo "pass = ${admin_pass}";
    echo "traits_queue = bltraits";
    echo "decomp_queue = bldecomp";
    echo "ca = /config/binlex-public-ca.pem";
    echo "cert = /config/binlex-client.crt";
    echo "key = /config/binlex-client.key";
    echo "port = ${rabbitmq_port}";
    echo "host = $2";
    echo "[minio]";
    echo "tls = yes";
    echo "host = $3";
    echo "port = ${minio_api_port}";
    echo "user = ${admin_user}";
    echo "pass = ${admin_pass}";
    echo "ca = /config/binlex-public-ca.pem";
}

function blapi_nginx_config_init(){
    echo "server {";
    echo "  listen 8080 default_server;";
    echo "  server_name _;";
    echo "  return 301 https://\$host:${blapi_https_port}\$request_uri;";
    echo "}";
    echo "server {";
    echo "  listen 8443 ssl;";
    echo "  server_name _;";
    echo "  ssl_certificate /config/$1;";
	echo "  ssl_certificate_key /config/$2;";
	echo "  sendfile on;";
	echo "  client_max_body_size 24M;";
	echo "  server_tokens off;";
    echo "  proxy_connect_timeout   600;";
    echo "  proxy_send_timeout      600;";
    echo "  proxy_read_timeout      600;";
    echo "  send_timeout            600;";
    echo "  proxy_buffering off;";
    echo "  client_header_buffer_size 8k;";
    echo "  location / {";
    echo "      add_header  Strict-Transport-Security \"max-age=31536000; includeSubDomains\";";
    echo "      proxy_pass  http://127.0.0.1:5000/;";
    echo "      proxy_http_version 1.1;";
    echo "      proxy_set_header Connection \"\";";
    echo "  }";
    echo "}";
}

function rabbitmq_config_init(){
    echo "listeners.tcp = none";
    echo "loopback_users.guest = false";
    echo "listeners.ssl.default = 0.0.0.0:5672";
    echo "cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config";
    for i in $(seq 1 $brokers); do
        echo "cluster_formation.classic_config.nodes.${i} = rabbit@rabbitmq-broker${i}";
    done
    echo "ssl_options.cacertfile = /config/binlex-public-ca.pem";
    echo "ssl_options.certfile = /config/$1.crt";
    echo "ssl_options.keyfile = /config/$1.key";
    echo "ssl_options.verify = verify_peer";
    echo "ssl_options.fail_if_no_peer_cert = true";
    echo "management.ssl.port = 15672";
    echo "management.ssl.cacertfile = /config/binlex-public-ca.pem";
    echo "management.ssl.certfile = /config/$1.crt";
    echo "management.ssl.keyfile = /config/$1.key";
}

function docker_rabbitmq_policy_init(){
    echo "#!/usr/bin/env bash";
    echo -n "docker exec -it rabbitmq-broker1 rabbitmqctl set_policy ha-fed '.*' '{\"federation-upstream-set\":\"all\", \"ha-sync-mode\":\"automatic\", \"ha-mode\":\"nodes\", \"ha-params\":[";
    for i in $(seq 1 $brokers); do
        echo -n "\"rabbit@rabbitmq-broker${i}\",";
    done | sed 's/,$//'
    echo "]}' --priority 1 --apply-to queues";
}

function docker_rabbitmq_plugin_init(){
    echo "#!/usr/bin/env bash";
    echo "docker exec -it $1 rabbitmq-plugins enable rabbitmq_federation";
}

function docker_rabbitmq_plugins_init(){
    echo "#!/usr/bin/env bash";
    for i in $(seq 1 $brokers); do
        echo "./rabbitmq-init-plugin-broker${i}.sh";
    done
}

function admin_init(){
    echo "use admin;";
    echo "db.createUser({"
    echo "  user: \"${admin_user}\",";
    echo "  pwd: \"${admin_pass}\",";
    echo "  roles: [";
    echo "      {role: \"clusterAdmin\", db: \"admin\"},";
    echo "      \"userAdminAnyDatabase\","
    echo "      \"readWriteAnyDatabase\"";
    echo "  ],";
    echo "  mechanisms:[\"SCRAM-SHA-1\"]";
    echo "});"
}

function mongodb_createuser(){
    echo "#!/usr/bin/env bash";
    echo "docker exec -it mongodb-router1 bash -c \"echo -e 'use binlex;\\ndb.createUser({user:\\\"\$1\\\",pwd:\\\"\$2\\\",roles:[{role:\\\"read\\\",db:\\\"binlex\\\"}],mechanisms:[\\\"SCRAM-SHA-1\\\"]});' | mongosh 127.0.0.1:27017 --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames -u \\\"${admin_user}\\\" -p \\\"${admin_pass}\\\" --authenticationDatabase admin\""
}

function db_init(){
    echo "use ${initdb};";
    echo "db.createUser({user:\"${username}\",pwd:\"${password}\",roles:[{role:\"readWrite\",db:\"binlex\"}],mechanisms:[\"SCRAM-SHA-1\"]});"
    cat schema.js
}

function router_init(){
    echo "#!/usr/bin/env bash";
    for i in $(seq 1 $shards); do
        for j in $(seq 1 $replicas); do
            echo "sh.addShard(\"shard${i}/mongodb-shard${i}-rep${j}:${mongodb_port}\");";
        done
    done
}

function shard_init(){
    echo "rs.initiate({_id: \"shard$1\", members: [";
    for i in $(seq 1 $replicas); do
        echo "  {_id: `expr ${i} - 1`, host: \"mongodb-shard$1-rep${i}:${mongodb_port}\"},";
    done
    echo "]});";
}

function cfg_init(){
    echo "rs.initiate({_id: \"${configdb}\", configsvr: true, members: [";
    for i in $(seq 1 $replicas); do
        echo "  {_id: `expr ${i} - 1`, host: \"mongodb-config-rep${i}:${mongodb_port}\"},";
    done
    echo "]});";
}

function docker_cfg_init(){
    echo "#!/usr/bin/env bash";
    echo "docker cp init-cfgs.js mongodb-config-rep1:/tmp/init-cfgs.js"
    echo "docker exec -it mongodb-config-rep1 bash -c \"cat /tmp/init-cfgs.js | mongosh 127.0.0.1:27017 --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames\"";
}

function docker_admin_init(){
    echo "#!/usr/bin/env bash";
    echo "docker cp init-admin.js mongodb-router1:/tmp/init-admin.js";
    echo "docker exec -it mongodb-router1 bash -c \"cat /tmp/init-admin.js | mongosh 127.0.0.1:${mongodb_port} --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames\"";
}

function docker_shard_init(){
    echo "#!/usr/bin/env bash";
    echo "docker cp init-shard$1.js mongodb-shard$1-rep1:/tmp/init-shard$1.js";
    echo "docker exec -it mongodb-shard$1-rep1 bash -c \"cat /tmp/init-shard$1.js | mongosh 127.0.0.1:${mongodb_port} --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames\"";
}

function docker_router_init(){
    echo "#!/usr/bin/env bash";
    echo "docker cp init-router.js mongodb-router1:/tmp/init-router.js";
    echo "docker exec -it mongodb-router1 bash -c \"cat /tmp/init-router.js | mongosh 127.0.0.1:${mongodb_port} --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames -u \\\"${admin_user}\\\" -p \\\"${admin_pass}\\\" --authenticationDatabase admin\""
}

function docker_db_init(){
    echo "#!/usr/bin/env bash";
    echo "docker cp init-db.js mongodb-router1:/tmp/init-db.js";
    echo "docker exec -it mongodb-router1 bash -c \"cat /tmp/init-db.js | mongosh 127.0.0.1:${mongodb_port} --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames -u \\\"${admin_user}\\\" -p \\\"${admin_pass}\\\" --authenticationDatabase admin\""
}

function docker_shards_init(){
    echo "#!/usr/bin/env bash";
    for i in $(seq 1 $shards); do
        echo "./init-shard${i}.sh";
    done
}

function docker_all_init(){
    echo "#!/usr/bin/env bash";
    echo "until ./init-cfgs.sh; do";
    echo "  sleep 10;";
    echo "done";
    echo "until ./init-shards.sh; do";
    echo "  sleep 10;";
    echo "done";
    echo "until ./init-admin.sh; do";
    echo "  sleep 10;";
    echo "done";
    echo "until ./init-router.sh; do";
    echo "  sleep 10;";
    echo "done";
    echo "until ./init-db.sh; do";
    echo "  sleep 10;";
    echo "done";
    echo "until ./rabbitmq-init-plugins.sh; do";
    echo "  sleep 10;";
    echo "done";
    echo "until ./rabbitmq-init-policy.sh; do";
    echo "  sleep 10;";
    echo "done";
}

function docker_admin_shell(){
    echo "#!/usr/bin/env bash";
    echo "docker exec -it \$1 mongosh 127.0.0.1:${mongodb_port} --tls --tlsCertificateKeyFile /config/binlex-client.pem --tlsCAFile /config/binlex-public-ca.pem --tlsAllowInvalidHostnames -u \\\"${admin_user}\\\" -p \\\"${admin_pass}\\\" --authenticationDatabase admin"
}

cfg_init > scripts/init-cfgs.js
docker_cfg_init > scripts/init-cfgs.sh
chmod +x scripts/init-cfgs.sh
for i in $(seq 1 $shards); do
    shard_init ${i} > scripts/init-shard${i}.js;
done
router_init > scripts/init-router.js
db_init > scripts/init-db.js
admin_init > scripts/init-admin.js
docker_admin_init > scripts/init-admin.sh
chmod +x scripts/init-admin.sh

for i in $(seq 1 $shards); do
    docker_shard_init ${i} > scripts/init-shard${i}.sh;
    chmod +x scripts/init-shard${i}.sh;
done

docker_shards_init > scripts/init-shards.sh
chmod +x scripts/init-shards.sh

docker_router_init > scripts/init-router.sh
chmod +x scripts/init-router.sh

docker_db_init > scripts/init-db.sh
chmod +x scripts/init-db.sh

docker_all_init > scripts/init-all.sh
chmod +x scripts/init-all.sh

docker_admin_shell > scripts/mongodb-shell.sh
chmod +x scripts/mongodb-shell.sh

mongodb_createuser > scripts/mongodb-createuser.sh
chmod +x scripts/mongodb-createuser.sh

mkdir -p config/

for i in $(seq 1 $brokers); do
    rabbitmq_config_init rabbitmq-broker${i} > config/rabbitmq-broker${i}.conf;
done

for i in $(seq 1 $brokers); do
    docker_rabbitmq_plugin_init rabbitmq-broker${i} > scripts/rabbitmq-init-plugin-broker${i}.sh;
    chmod +x scripts/rabbitmq-init-plugin-broker${i}.sh;
done

docker_rabbitmq_plugins_init > scripts/rabbitmq-init-plugins.sh;
chmod +x scripts/rabbitmq-init-plugins.sh;

docker_rabbitmq_policy_init > scripts/rabbitmq-init-policy.sh
chmod +x scripts/rabbitmq-init-policy.sh

for i in $(seq 1 $blapi_users); do
    cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1 >> config/blapi_user.keys
done

for i in $(seq 1 $blapi_admins); do
    cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1 >> config/blapi_admin.keys
done

minio_iter=1
rabbitmq_iter=1
mongodb_iter=1
for i in $(seq 1 $blapis); do
    blapi_config_init mongodb-router${mongodb_iter} rabbitmq-broker${rabbitmq_iter} minio${minio_iter}> config/blapi${i}.conf;
    blapi_nginx_config_init blapi${i}.crt blapi${i}.key > config/blapi${i}_nginx.conf;
    if [ ${rabbitmq_iter} -eq $brokers ]; then
        rabbitmq_iter=1;
    else
        rabbitmq_iter=$((rabbitmq_iter+1));
    fi
    if [ ${mongodb_iter} -eq $routers ]; then
        mongodb_iter=1;
    else
        mongodb_iter=$((mongodb_iter+1));
    fi
    if [ ${minio_iter} -eq $minios ]; then
        minio_iter=1;
    else
        minio_iter=$((minio_iter+1));
    fi
done

rabbitmq_iter=1
mongodb_iter=1
for i in $(seq 1 $bldbs); do
    bldb_config_init mongodb-router${mongodb_iter} rabbitmq-broker${rabbitmq_iter} > config/bldb${i}.conf
    if [ ${rabbitmq_iter} -eq $brokers ]; then
        rabbitmq_iter=1;
    else
        rabbitmq_iter=$((rabbitmq_iter+1));
    fi
    if [ ${mongodb_iter} -eq $routers ]; then
        mongodb_iter=1;
    else
        mongodb_iter=$((mongodb_iter+1));
    fi
done

rabbitmq_iter=1
minio_iter=1
for i in $(seq 1 $bldbs); do
    bldec_config_init rabbitmq-broker${rabbitmq_iter} minio${minio_iter}> config/bldec${i}.conf
    if [ ${rabbitmq_iter} -eq $brokers ]; then
        rabbitmq_iter=1;
    else
        rabbitmq_iter=$((rabbitmq_iter+1));
    fi
    if [ ${minio_iter} -eq $minios ]; then
        minio_iter=1;
    else
        minio_iter=$((minio_iter+1));
    fi
done

prometheus_config_init > config/prometheus.yml

function generate_creds(){
    echo "---BEGIN CREDENTIALS--";
    echo "${admin_user}:${admin_pass}";
    echo "${username}:${password}";
    echo "bljupyter_token:${bljupyter_token}";
    echo "blapi admin keys:";
    cat config/blapi_admin.keys;
    echo "blapi user keys:";
    cat config/blapi_user.keys
    echo "---END CREDENTIALS---";
}

generate_creds | tee config/credentials.txt

# if [ ! -f scripts/rabbitmqadmin ]; then
#     wget "https://raw.githubusercontent.com/rabbitmq/rabbitmq-server/v${rabbitmq_version}/deps/rabbitmq_management/bin/rabbitmqadmin" -O scripts/rabbitmqadmin;
#     chmod +x scripts/rabbitmqadmin;
# fi

# if [ ! -f scripts/mongosh ]; then
#     wget "https://downloads.mongodb.com/compass/mongodb-mongosh_${mongodb_sh_version}_amd64.deb" -O scripts/mongosh.deb;
#     dpkg --fsys-tarfile scripts/mongosh.deb | tar xOf - ./usr/bin/mongosh > scripts/mongosh;
#     chmod +x scripts/mongosh;
# fi
