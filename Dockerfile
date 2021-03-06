FROM centos:7
MAINTAINER Vašek Pavlín <vasek@redhat.com>

EXPOSE 8080
CMD entrypoint.sh

RUN yum -y install epel-release &&\
    yum -y install jq &&\
    yum -y remove epel-release &&\
    yum clean all

RUN mkdir -p /opt/jenkins-dreamer &&\
    chgrp -R 0 /opt/jenkins-dreamer &&\
    chmod -R g+rw /opt/jenkins-dreamer &&\
    find /opt/jenkins-dreamer -type d -exec chmod g+x {} +

WORKDIR /opt/jenkins-dreamer
ADD health_check.sh /opt/jenkins-dreamer/
RUN chmod +x /opt/jenkins-dreamer/health_check.sh

ADD dreamer.sh /opt/jenkins-dreamer/
RUN chmod +x /opt/jenkins-dreamer/dreamer.sh

ADD entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh