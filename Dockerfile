FROM centos:7
MAINTAINER Vašek Pavlín <vasek@redhat.com>

EXPOSE 8080

#Taken from https://github.com/kbsingh/openshift-nginx/blob/master/Dockerfile
ADD https://raw.githubusercontent.com/kbsingh/openshift-nginx/master/yum-repo-nginx-testing.repo /etc/yum.repos.d/nginx-testing.repo

RUN yum -y install --setopt=tsflags=nodocs epel-release && \
    yum -y --enablerepo=nginx-testing install --setopt=tsflags=nodocs nginx && \
    yum clean all && \
    mkdir -p /usr/share/nginx/html

RUN yum -y install epel-release &&\
    yum -y install jq &&\
    yum -y remove epel-release &&\
    yum clean all

RUN mkdir -p /opt/jenkins-dreamer &&\
    chgrp -R 0 /opt/jenkins-dreamer &&\
    chmod -R g+rw /opt/jenkins-dreamer &&\
    find /opt/jenkins-dreamer -type d -exec chmod g+x {} +

RUN rm -rf /etc/nginx/conf.d/default.conf

RUN rm /usr/share/nginx/html/*

RUN chgrp -R 0 /usr/share/nginx/html &&\
    chmod -R g+rwX /usr/share/nginx/html &&\
    chmod +x /usr/share/nginx/html

RUN chgrp -R 0 /var/log/nginx &&\
    chmod -R g+rwX /var/log/nginx &&\
    chmod +x /var/log/nginx

RUN chgrp -R 0 /run &&\
    chmod -R g+rwX /run &&\
    chmod +x /run

WORKDIR /opt/jenkins-dreamer
ADD health_check.sh /opt/jenkins-dreamer/
RUN chmod +x /opt/jenkins-dreamer/health_check.sh

ADD dreamer.sh /opt/jenkins-dreamer/
RUN chmod +x /opt/jenkins-dreamer/dreamer.sh

ADD entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh

ADD root /

CMD entrypoint.sh