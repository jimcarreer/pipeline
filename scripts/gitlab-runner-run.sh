source settings
mkdir $DOCKER_VOL/gitlab-runner
mkdir $DOCKER_VOL/gitlab-runner/config
mkdir $DOCKER_VOL/gitlab-runner/runner-home
docker run --detach \
    --net pipeline \
    --net-alias gitlab-runner.internal \
    --hostname gitlab-runner.$DOCKER_PIPELINE_DNSROOT \
    --name gitlab-runner \
    --restart always \
    --volume $DOCKER_VOL/gitlab-runner/config:/etc/gitlab-runner \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume $DOCKER_VOL/gitlab-runner/runner-home:/home/gitlab-runner \
    --volume $DOCKER_CA_CERT:/etc/gitlab-runner/certs/ca.crt:ro \
    gitlab/gitlab-runner:latest
docker exec -it gitlab-runner gitlab-runner register
