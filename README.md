# Table of Contents
1. [Foreword and Audience](#foreword-and-audience)
2. [Software Used](#software-used)
3. [Step by Step Guide](#step-by-step-guide)
   1.  [Prerequisites](#prerequisites)
   2.  [Certificates](#certificates)
   3.  [Prepare your workspace](#prepare-your-workspace)
   4.  [NGINX Setup](#nginx-setup)
   5.  [GitLab Setup](#gitlab-setup)
   6.  [Artifactory Setup](#artifactory-setup)
   7.  [GitLab Runner Setup](#gitLab-runner-setup)
   8.  [Setup Docker Registry](#setup-docker-registry)
   9.  [Create a Custom Build Agent Image](#create-a-custom-build-agent-image)
   10. [Example Project](#example-project)
4. [References](#references)

# Foreword and Audience
I primarily sat down to do this for fun.  I've always enjoyed building systems like this and found myself with some free time to do so.  I also wanted an excuse to really get to know the more interesting features of docker.  This guide is mostly designed to help jump start someone who needs to create a build pipeline for a multi-developer environment and uses the free versions of several quality pieces of software that have feature rich commercial licensing options.  The setup we're building today is primarily geared toward Java and other JVM language development (Groovy / Scala / Kotlin) but could be modified for other programming languages and environments.

This guide does not cover production deployment or management of that process though I may expand it later for that situation, it is mainly geared toward the Build Engineering side of DevOps.

This guide assumes the reader is a fairly competent Linux administrator and has a good foundation in programming, source control with git, and basic networking concepts.

# Software Used
Here I'll briefly go over some of the software used and a short description of their purpose.

| Software                                              | Purpose                                                      |
| ----------------------------------------------------- | ------------------------------------------------------------ |
| [Docker](https://www.docker.com/)                     | Installation and management of other build pipeline software |
| [NGINX](https://www.nginx.com/)                       | Domain routing / ingress control                             |
| [GitLab CE](https://about.gitlab.com/)                | Source control and build pipelining                          |
| [Artifactory OSS](https://www.jfrog.com/artifactory/) | Build artifact publishing and management                     |

Some topics about each we'll generally cover include

1. Using .gitlab-ci.yml files for creating build pipelines for our projects
2. Using NGINX for ingress control and routing
3. Using Docker and gitlab-runner to build and test our code
4. Publishing tested builds to Artifactory for consumption by developers

Some other topics covered but primarily play supporting roles include

1. Creating custom Docker images and publishing them to a private registry
2. Certificate authority and certificate management
3. Docker networking

Both GitLab and Artifactory have more feature rich commercial versions. One draw back of Artifactory is that its open source version is rather restrictive about the types of repositories that you can make.  It does have the ability to act as a standard repository for all manner of binary artifacts, including RPMs, Docker images and more, however the free version is generally restricted to a handful of repository options.  The pricing is a little steep, starting at 3000$ for the "Pro" version, but considering the range of features it provides it might be worth it, especially if software is your primary business and you intend to grow your development team.

At some point I may investigate the use of Nexus over Artifactory.  Really I only chose Artifactory because it came highly recommended and did look a bit easier to use.

# Step by Step Guide

## Prerequisites

This guide assumes you already have a sever running to use as your Docker host.  This guide uses CentOS Server 7 as I just happen to like CentOS, however there is no reason the guide could not be extrapolated to Ubuntu, Arch, or whatever distribution you happen to prefer.  Most of the work we will be doing will rely very little on the host OS chosen.  Administrative or "root" access to the Docker host operating system, while not entirely necessary, is recommended.  This guide also assumes that Docker is installed and running.  The majority of files and work being done on the host OS will be done so from /opt/example/ which will be the root directory we use for our configurations, Docker scripts, Docker volumes and other miscellanea, you should choose a location appropriate for your situation.  All domains and certificates will be for "example.com" which you should obviously replace with your own domain.

## Certificates

In this step we will generate a self signed certificate authority and sign a request for a certificate with several SAN (Subject Alternative Names) entries for the various components of our pipeline.  Primarily, NGINX will be using this for encrypting access to the various services we will expose.  You might ask, "why bother doing this, SSL just makes everything more complicated?" to which I would respond (you may just want to skip my rambling):

>In an age where security is becoming increasingly important anyone doing anything in IT or Software should have a basic understanding of Certificate Management and Encryption with SSL. Generally I've found that it makes things easier in the future if you have the ability to produce signed certificates, a lot of software and services assume encrypted communication by default, and its easier (and more secure) to pop your company's certificate authority into trust chains than it is to reconfigure them to not use encryption.  A good example of this might be that later we want to integrate Artifactory and GitLab with Active Directory or LDAP to have singular control over user access to these systems.  We'd want this communication to be encrypted and having our custom authority installed on these components already would make that even easier.

If your company already has a certificate authority you may consider skipping the generation of a new one in lieu of just asking your IT department to sign the certificate request we will generate for our services. Make sure to also get the public key as well.

### Generate a certificate authority

```
[root@dockerhost]> mkdir certs
[root@dockerhost]> mkdir ca
[root@dockerhost]> cd certs/ca
[root@dockerhost]> openssl genrsa -des3 -out example.com.ca.key 2048
Generating RSA private key, 2048 bit long modulus
....................................+++
.........+++
e is 65537 (0x10001)
Enter pass phrase for example.com.ca.key:
Verifying - Enter pass phrase for example.com.ca.key:
```

Here we're generating a 2048 bit password protected certificate we'll use as our authority. Most people consider 2048 to be "good enough", if you're paranoid you may want to use 4096, but as of this guide's writing that is a bit overboard.  Additionally you may notice that I use the extensions ".key" for private keys and ".crt" for the public keys, this is just a convention I like, some people like ".key" and ".pem".

### Self-sign the certificate

Obviously your certificate details will vary:

```
[root@dockerhost]> openssl req -x509 -nodes -key example.com.ca.key -sha256 -days 1095 -out example.com.ca.crt -new
Enter pass phrase for example.com.ca.key:
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) [XX]:US
State or Province Name (full name) []:KY
Locality Name (eg, city) [Default City]:Louisville
Organization Name (eg, company) [Default Company Ltd]:Example Ltd
Organizational Unit Name (eg, section) []:Example Department
Common Name (eg, your name or your server's hostname) []:Example
Email Address []:it@example.com
```

Now you have your own certificate authority that expires in 1095 days (3 years). We'll be using this to sign other certificates we issue.  So that Docker on your Docker host trusts certificates signed by this authority, go ahead and copy it to ```/etc/docker/certs.d/docker.dev.example.com/ca.crt``` or the equivalent path for your situation.  Later when we create a Docker registry with this domain name our instance of Docker will trust the certificate being presented by it.

### Generate and sign a certificate for pipeline services

First we're going to create an openssl configuration file, use your favorite editor to create a file similar to this:
```
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
[ req_distinguished_name ]
countryName  = Country Name (2 letter code)
stateOrProvinceName  = State or Province Name (full name)
localityName = Locality Name (eg, city)
organizationName = Organization Name (eg, company)
commonName = Common Name (e.g. server FQDN or YOUR name)
[ req_ext ]
subjectAltName = @alt_names
[alt_names]
DNS.1 = dev.example.com
DNS.2 = docker.dev.example.com
DNS.3 = gitlab.dev.example.com
DNS.4 = artifactory.dev.example.com
```

Next create a new key
```
[root@dockerhost]> openssl genrsa -out dev.example.com.key 2048
Generating RSA private key, 2048 bit long modulus
..........................+++
....+++
e is 65537 (0x10001)
```

Generate a certificate signing request for this key
```
[root@dockerhost]> openssl req -new -out dev.example.com.csr -key dev.example.com.key -config dev.example.com.cnf
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) []:US
State or Province Name (full name) []:KY
Locality Name (eg, city) []:Louisville
Organization Name (eg, company) []:Example
Common Name (e.g. server FQDN or YOUR name) []:dev.example.com
```

Sign the request, move your certificates to a more appropriate place, and clean up the temporary files
```
[root@dockerhost]> openssl x509 -req -in dev.example.com.csr -extfile dev.example.com.cnf -extensions req_ext -CA example.com.ca.crt -CAkey example.com.ca.key -out dev.example.com.crt -days 1095 -sha256
Signature ok
subject=/C=US/ST=KY/L=Louisville/O=Example/CN=dev.example.com
Getting CA Private Key
Enter pass phrase for example.com.ca.key:
[root@dockerhost]> rm dev.example.com.csr
[root@dockerhost]> rm dev.example.com.cnf
[root@dockerhost]> mv dev.example.com.key ../
[root@dockerhost]> mv dev.example.com.crt ../
```

_Note_: You might be familiar with "wild card" domain names, and may be wondering: "why not just specify our Common Name as \*.dev.example.com?".  Originally when I was setting this up, that's exactly what I did.  What I found that was problematic was that it seems many entities (such as Google / Chrome) are moving to requiring SANs in certificates for scenarios like this, probably because it's more secure.  It does make a kind of sense, you should be very explicit in what names your certificate covers, and since I hadn't created a certificate with SANs I figured this would be a good opportunity to explore.

## Prepare your workspace

When working on projects like this I like to choose a root directory for all my Docker volumes, in this case we're simply going to make directory called "volumes".  We'll also be creating a Docker network "pipeline", an internal network that the various services we're installing will use to interact
```
[root@dockerhost]> mkdir volumes
[root@dockerhost]> docker network create pipeline
```

Finally add a couple of entries ```/etc/hosts/``` to your Docker host, as well as any systems you plan to access the various new services from:
```
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
192.168.1.133 gitlab.dev.example.com docker.dev.example.com artifactory.dev.example.com dev.example.com
```
Here 192.168.1.133 is the IP of my Docker host.  If you run and manage your own DNS server you should probably add an entry there instead of modifying host files.

## NGINX Setup

Now we're going to setup NGINX and give it a basic configuration
```
[root@dockerhost]> mkdir -p /opt/example/volumes/nginx/
[root@dockerhost]> mkdir -p /opt/example/volumes/nginx/conf.d/
[root@dockerhost]> docker run --detatch \
  --net pipeline \
  --net-alias nginx.dev.example.com \
  --hostname nginx.dev.example.com \
  --publish 443:443 \
  --name nginx \
  --restart always \
  --volume /opt/example/volumes/nginx/conf.d/:/etc/nginx/conf.d/:ro \
  --volume /opt/example/certs/dev.example.com.crt:/etc/certs/nginx.crt:ro \
  --volume /opt/example/certs/dev.example.com.key:/etc/certs/nginx.key:ro \
  nginx
```
We're mounting all these volumes as "read only" because there is no reason for NGINX to to modify any of these files.  You could get fancier and mount log directories as well so that you can view NGINX logs more easily from the host system, but that is an exercise left to the reader.  Next create a configuration in ```volumes/nginx/conf.d/``` called "pipeline.conf" which will be the NGINX configuration we use to allow ingress to the various services from our Docker network.  By default we'll be opening port 443 and routing all requests to a 404 page.  As we add more services, we'll modify this configuration so that we can access those services.
```
server {
    listen               443 ssl;
    ssl_certificate      /etc/certs/nginx.crt;
    ssl_certificate_key  /etc/certs/nginx.key;
    ssl_protocols        TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers          HIGH:!aNULL:!MD5;
    location / {
        return 404;
    }
}
```

## GitLab Setup

Start a GitLab container
```
[root@dockerhost]> mkdir -p /opt/example/volumes/gitlab
[root@dockerhost]> mkdir -p /opt/example/volumes/gitlab/logs
[root@dockerhost]> mkdir -p /opt/example/volumes/gitlab/data
[root@dockerhost]> mkdir -p /opt/example/volumes/gitlab/config
[root@dockerhost]> docker run --detach \
  --env GITLAB_OMNIBUS_CONFIG="
        external_url 'https://gitlab.dev.example.com';
        gitlab_rails['gitlab_shell_ssh_host'] = 'gitlab.dev.example.com';
        gitlab_rails['gitlab_shell_ssh_port'] = 64022;
        nginx['listen_https'] = false;
        nginx['listen_port'] = 80;" \
  --net pipeline \
  --net-alias gitlab.internal \
  --hostname gitlab.dev.example.com \
  --publish 64022:22 \
  --name gitlab \
  --restart always \
  --volume /opt/example/volumes/gitlab/config:/etc/gitlab \
  --volume /opt/example/volumes/gitlab/logs:/var/log/gitlab \
  --volume /opt/example/volumes/gitlab/data:/var/opt/gitlab \
  gitlab/gitlab-ce:latest
```
There are a couple things going on here:
1. We're using the ```GITLAB_OMNIBUS_CONFIG``` variable to set some important configurations for GitLab:
2. We're telling GitLab that the external URL we're using for is https://gitlab.dev.example.com generated links wont work properly.
3. We're telling GitLab we're using 64022 for external SSH connections, you'll also notice we're publishing 64022 on the Docker host.
4. We're telling GitLab's instance of NGINX to listen on port 80 and to not bother enabling HTTPS since we have our own NGINX instance handling this.

_Note_: If you really wanted to optimize this setup, you can potentially tell GitLab not to run NGINX at all and to instead use the instance we setup.  This would require more complex GitLab and NGINX configuration and didn't seem worth it to me.

Add the following section to the NGINX config
```
server {
    listen              443 ssl;
    server_name         gitlab.dev.example.com;
    ssl_certificate     /etc/certs/nginx.crt;
    ssl_certificate_key /etc/certs/nginx.key;
    ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    location / {
        proxy_pass http://gitlab.internal:80;
        proxy_set_header Host $http_host;
    }
}
```
Then restart NGINX
```
[root@dockerhost]> docker restart nginx
```

It's very important to set ```proxy_set_header Host $http_host;``` as GitLab uses the Host header to perform redirections.  If it is not set GitLab will incorrectly use the Docker network's alias ```gitlab.internal``` in some cases.

If everything is working properly, you should be able to navigate to https://gitlab.dev.example.com where you will be prompted to enter the root user's password.  Once this is setup go ahead and create an administrative user and a new project repository called "test".  We'll be using this repository later create a basic project that GitLab will build, run and then publish to Artifactory.

## Artifactory Setup

Start an Artifactory container
```
[root@dockerhost]> mkdir -p /opt/example/volumes/artifactory
[root@dockerhost]> docker run --detach \
  --net pipeline \
  --net-alias artifactory.internal \
  --hostname artifactory.dev.example.com \
  --name artifactory \
  --restart always \
  --volume /opt/example/volumes/artifactory:/var/opt/jfrog/artifactory \
  docker.bintray.io/jfrog/artifactory-oss:latest
```
Add the following section to the NGINX config
```
server {
    listen              443 ssl;
    server_name         artifactory.dev.example.com;
    ssl_certificate     /etc/certs/nginx.crt;
    ssl_certificate_key /etc/certs/nginx.key;
    ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
       return 301 https://artifactory.dev.example.com/artifactory/webapp/;
    }

    location /artifactory {
        proxy_pass http://artifactory.internal:8081;
        proxy_set_header Host $http_host;
        proxy_set_header X-Artifactory-Override-Base-Url https://artifactory.dev.example.com/artifactory;
    }
}
```
Then restart NGINX.  A couple of things to explain in this configuration:
1) We redirect / calls to Artifactory https://artifactory.dev.example.com/artifactory/webapp/ because I found that Artifactory's method of redirection seemed broken for reverse proxies.
2) We set the X-Artifactory-Override-Base-Url header so that Artifactory knows how it is accessed externally
```
[root@dockerhost]> docker restart nginx
```
Setup your admin password for Artifactory, you shouldn't need proxy settings.  Additionally you may want to go ahead and use Artifactoy's quick setup to create a couple of Gradle repositories, by default the quick setup will create dev and release repositories.  Finally I'd recommend creating a user "build-agent" that is specifically for uploading artifacts from our build jobs.  If you do this, remember to grant it access to the repositories created during setup.  For more information on this, see Artifactory's [permissions documentation](https://www.jfrog.com/confluence/display/RTF/Managing+Permissions).

## GitLab Runner Setup

To use GitLab's CI/CD capabilities to build, test, and publish code, we're going to need GitLab Runner.  GitLab Runner is a service that polls GitLab looking for jobs to run, then executes them via Docker, VirtualBox, Parrallels, Kubernetes and more.  Because we're already using Docker extensively, the only executor we will configure for now will be one using Docker on the host.
```
[root@dockerhost]> mkdir /opt/example/volumes/gitlab-runner
[root@dockerhost]> mkdir /opt/example/volumes/gitlab-runner/config
[root@dockerhost]> mkdir /opt/example/volumes/gitlab-runner/runner-home
[root@dockerhost]> docker run --detach \
    --net pipeline \
    --net-alias gitlab-runner.internal \
    --hostname gitlab-runner.dev.example.com \
    --name gitlab-runner \
    --restart always \
    --volume /opt/example/volumes/gitlab-runner/config:/etc/gitlab-runner \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume /opt/example/volumes/gitlab-runner/runner-home:/home/gitlab-runner \
    --volume /opt/example/certs/ca/example.com.ca.crt:/etc/gitlab-runner/certs/ca.crt:ro \
    gitlab/gitlab-runner:latest
```
One thing you'll notice we're doing here is mounting ```/var/run/docker.sock``` from the Docker host to our container.  This will allow our GitLab Runner to run containers directly on the Docker host.

_Note_: If you're on a system that has SELinux enabled (such as CentOS), you may have to install a permissions module to allow a Docker container to interact with the Docker host in this way.  Some signs you may need to do this are "Permission denied" errors in your GitLab Runner logs.  The module source with instructions on installation can be found [here](https://github.com/dpw/selinux-dockersock).  Alternatively you can just disable SELinux but I do not advise this.

Once the container is running we then need to register it to our GitLab instance so that it can receive jobs.
```
[root@dockerhost]> docker exec -it gitlab-runner gitlab-runner register
Running in system-mode.                            
                                                   
Please enter the gitlab-ci coordinator URL (e.g. https://gitlab.com/):
http://gitlab.internal
Please enter the gitlab-ci token for this runner:
CTufxF15xxxxxxxxxxxx
Please enter the gitlab-ci description for this runner:
[gitlab-runner.dev.example.com]: Dockerized Runner  
Please enter the gitlab-ci tags for this runner (comma separated):

Whether to lock the Runner to current project [true/false]:
[true]: false
Registering runner... succeeded                     runner=CTufxF15
Please enter the executor: docker-ssh, parallels, shell, docker+machine, docker, ssh, virtualbox, docker-ssh+machine, kubernetes:
docker
Please enter the default Docker image (e.g. ruby:2.1):
java:8-jdk
Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded!
```
We're prompted for a few things here.  A couple that are important are the coordinator, which is our GitLab instance, and the token, which you can find by going to the test project you created when setting up Gitlab under Settings > CI/CD and expanding the "General Pipeline Settings" section in GitLab.  You'll notice we're also setting the default image to "java:8-jdk", this is primarily because our setup will be building JVM based projects.  Finally we're not locking this runner to the specific project, in the future we might reuse it for other projects.

## Setup Docker Registry

Next we'll run our own Docker Registry.  We're primarily going to use this for storing custom images for building and testing our software.  However you could later use the same registry to store Docker images that actually run the software you're building, say for example if you have a microservice architecture.
```
[root@dockerhost]> docker run --detach \
    --net pipeline \
    --env REGISTRY_HTTP_ADDR=0.0.0.0:80 \
    --net-alias docker.internal \
    --hostname docker.dev.example.com \
    --name docker-registry \
    --restart always \
    registry:2
```

_Note_: I'd love to actually use Artifactory as my Docker Registry, it appears to have that feature, but only if you a licensed version.

Add the following section to the NGINX config:
```
server {
    listen                    443 ssl;
    server_name               docker.dev.example.com;
    ssl_certificate           /etc/certs/nginx.crt;
    ssl_certificate_key       /etc/certs/nginx.key;
    ssl_protocols             TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers               HIGH:!aNULL:!MD5;
    client_max_body_size      0;
    chunked_transfer_encoding on;

    location / {
        auth_basic           "Docker Registry";
        auth_basic_user_file conf.d/docker.htpasswd;
        proxy_pass           http://docker.internal:80;
        proxy_set_header     Host $http_host;
        proxy_set_header     X-Real-IP $remote_addr;
        proxy_set_header     X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header     X-Forwarded-Proto $scheme;
        proxy_read_timeout   900;
    }
}
```
All of the ```proxy_set``` headers here are required especially for Docker Registry version 2.  We're also protecting access to the registry using HTTP Basic Authentication.  Chunked encoding must also be enabled to avoid NGINX from rejecting larger image uploads.  We need to generate the password file we're going to use for this authentication next:
```
[root@dockerhost]> echo -n "registryuser" > /opt/example/volumes/nginx/conf.d/docker.htpasswd
[root@dockerhost]> openssl passwd -apr1 >> /opt/example/volumes/nginx/conf.d/docker.htpasswd
Password:
Verifying - Password:
```

Next restart NGINX
```
[root@dockerhost]> docker restart nginx
```
Finally, use ```docker login``` to verify that everything is setup properly:
```
[root@dockerhost]> docker login -u registryuser docker.dev.example.com
Password:
```
If you receive an error like:
```Error response from daemon: Get https://docker.dev.example.com/v1/users/: x509: certificate signed by unknown authority``` 
It means you need to install your certificate authority for Docker to use on your Docker Host.  In our example that means copying ```example.com.ca.crt``` generated in the first step to ```/etc/docker/certs.d/docker.dev.example.com/```.  For Docker, certificate authorities are rooted at ```certs.d/<fully qualified domain name of server>```.

You should now be able to push and pull images to and from this repository.

## Create a Custom Build Agent Image

The first thing we'll do with our new registry is create a custom build agent image for our projects.  Specifically I mentioned that this tutorial was geared toward JVM based languages using Gradle to build and test, so the build agent we'll create now will be specifically for that purpose.  We'll be using the official JDK-8 image as our base, installing a specific version of Gradle on it, then also setting some environmental variables that will allow us to publish our artifacts to Artifactory.  Create a new directory in your working directory named "build-agent", change to that directory and pull down the version of Gradle you use, in my case it was 4.3.1:
```
[root@dockerhost]> mkdir -p /opt/example/build-agent/
[root@dockerhost]> cd /opt/example/build-agent/
[root@dockerhost]> cp /opt/example/certs/ca/example.com.ca.crt ca.crt
[root@dockerhost]> wget https://services.gradle.org/distributions/gradle-4.3.1-bin.zip
[root@dockerhost]> unzip gradle-4.3.1-bin.zip
[root@dockerhost]> rm gradle-4.3.1-bin.zip
```
We're going to be adding this directory to our build-agent image.  You should also copy your CA certificate to this directory as well as ```ca.crt``` we will be adding it to the image's various certificate store.  Next create a Dockerfile with the following content:
```
FROM java:8-jdk

ADD ./gradle-4.3.1/ /opt/gradle-4.3.1/
ADD ca.crt /usr/local/ca-certificates/cacert.crt

ENV PATH     "$PATH:/opt/gradle-4.3.1/bin/"
ENV ART_USER "build-agent"
ENV ART_PASS "test"
ENV ART_CURL "https://artifactory.dev.example.com/artifactory"

RUN update-ca-certificates
RUN keytool -import -alias 'pipelineca' -keystore $JAVA_HOME/jre/lib/security/cacerts -trustcacerts -file /usr/local/ca-certificates/cacert.crt -storepass changeit -noprompt
```
The ADD commands are adding our version of Gradle and our certificate authority to the image.  The ENV commands are setting various variables on the image so that we can use Gradle and interact with Artifactory.  Finally the RUN commands are adding our Certificate Authority to various keystores on the image.  Finally we'll build the image and push it to our registry:
```
docker build ./ --tag docker.dev.example.com/build-agents:8-jdk-431-gradle
docker push docker.dev.example.com/build-agents:8-jdk-431-gradle
```

## Example Project

Now that we have our infrastructure 

# References
1.  [Creating Your Own SSL Certificate Authority](https://datacenteroverlords.com/2012/03/01/creating-your-own-ssl-certificate-authority/)
2.  [FAQ/subjectAltName (SAN)](http://wiki.cacert.org/FAQ/subjectAltName)
3.  [GitLab Docker Images](https://docs.gitlab.com/omnibus/docker/README.html)
4.  [GitLab (bug): external_url setting doesn't work](https://gitlab.com/gitlab-org/omnibus-gitlab/issues/244)
5.  [Artifactory: Installing with Docker](https://www.jfrog.com/confluence/display/RTF/Installing+with+Docker)
6.  [Artifactory Permissions](https://www.jfrog.com/confluence/display/RTF/Managing+Permissions)
7.  [Run GitLab Runner in a container](https://docs.gitlab.com/runner/install/docker.html)
8.  [GitLab: Registering Runners](https://docs.gitlab.com/runner/register/index.html)
9.  [SELinux Docker Socket](https://github.com/dpw/selinux-dockersock)
10. [NGINX: Module ngx_http_auth_basic_module](http://nginx.org/en/docs/http/ngx_http_auth_basic_module.html#auth_basic)
11. [Docker Registry: Authenticate proxy with nginx](https://docs.docker.com/registry/recipes/nginx/#setting-things-up)