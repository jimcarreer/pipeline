source settings
echo -n "Docker username: "
read DOCKERUSER
echo -n "$DOCKERUSER:" >> $DOCKER_VOL/nginx/conf.d/docker.htpasswd
openssl passwd -apr1 >> $DOCKER_VOL/nginx/conf.d/docker.htpasswd
