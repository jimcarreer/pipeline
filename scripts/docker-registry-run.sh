source settings
echo "server {
    listen                    443 ssl;
    server_name               docker.dev.example.com;
    ssl_certificate           /etc/certs/nginx.crt;
    ssl_certificate_key       /etc/certs/nginx.key;
    ssl_protocols             TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers               HIGH:!aNULL:!MD5;
    client_max_body_size      0;
    chunked_transfer_encoding on;   
 
    location / {
        auth_basic           'Docker Registry';
        auth_basic_user_file conf.d/docker.htpasswd;
        proxy_pass           http://docker.internal:80;
        proxy_set_header     Host \$http_host;
        proxy_set_header     X-Real-IP \$remote_addr;
        proxy_set_header     X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header     X-Forwarded-Proto \$scheme;
        proxy_read_timeout   900;
    }
}" > $DOCKER_VOL/nginx/conf.d/1.docker.conf
docker run --detach \
    --net $DOCKER_PIPELINE_NET \
    --env REGISTRY_HTTP_ADDR=0.0.0.0:80 \
    --net-alias docker.internal \
    --hostname docker.$DOCKER_PIPELINE_DNSROOT \
    --name docker-registry \
    --restart always \
    registry:2
docker restart nginx
