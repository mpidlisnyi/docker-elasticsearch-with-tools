FROM mpidlisnyi/elasticsearch:2.0
MAINTAINER maksim@nightbook.info
LABEL version="0.1.1"

RUN apt-get update
RUN apt-get install --no-install-recommends --no-install-suggests -y ruby ruby-dev rubygems
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

RUN gem install --no-rdoc --no-ri aws-sdk -v 2.5.5
RUN gem install --no-rdoc --no-ri faraday -v 0.9.2

COPY scripts/es-cloudwatch-monitoring.rb /bin/es-cloudwatch-monitoring
RUN chmod +x /bin/es-cloudwatch-monitoring
