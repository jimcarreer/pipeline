source settings
mkdir -p ./build-agent/
cd ./build-agent
cp $DOCKER_CA_CERT ca.crt
wget https://services.gradle.org/distributions/gradle-4.3.1-bin.zip
unzip gradle-4.3.1-bin.zip
rm gradle-4.3.1-bin.zip
echo "
FROM java:8-jdk

ADD ./gradle-4.3.1/ /opt/gradle-4.3.1/
ADD ca.crt /usr/local/ca-certificates/cacert.crt

ENV PATH     \"\$PATH:/opt/gradle-4.3.1/bin/\"
ENV ART_USER \"$ARTIFACTORY_USER\"
ENV ART_PASS \"$ARTIFACTORY_PASS\"
ENV ART_CURL \"https://artifactory.$DOCKER_PIPELINE_DNSROOT/artifactory\"

RUN update-ca-certificates
RUN keytool -import -alias 'pipelineca' -keystore \$JAVA_HOME/jre/lib/security/cacerts \
-trustcacerts -file /usr/local/ca-certificates/cacert.crt -storepass changeit -noprompt
" > Dockerfile
docker build ./ --tag docker.$DOCKER_PIPELINE_DNSROOT/build-agents:8-jdk-431-gradle
