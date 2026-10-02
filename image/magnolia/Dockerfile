FROM tomcat:9-jdk11-temurin

ARG MAGNOLIA_VERSION=6.2.40
ARG MAGNOLIA_WAR_URL=https://nexus.magnolia-cms.com/repository/magnolia.public.releases/info/magnolia/bundle/magnolia-community-webapp/${MAGNOLIA_VERSION}/magnolia-community-webapp-${MAGNOLIA_VERSION}.war
ARG MAGNOLIA_WAR_SHA1=https://nexus.magnolia-cms.com/repository/magnolia.public.releases/info/magnolia/bundle/magnolia-community-webapp/${MAGNOLIA_VERSION}/magnolia-community-webapp-${MAGNOLIA_VERSION}.war.sha1

ARG POSTGRESQL_VERSION=42.2.18
ARG POSTGRESQL_JAR_URL=https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRESQL_VERSION}/postgresql-${POSTGRESQL_VERSION}.jar

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/magnolia/config/default /etc/magnolia/config/repo-conf /etc/magnolia/config/shared \
    && mkdir -p /opt/magnolia/data/deploy /opt/magnolia/data/repository /opt/magnolia/data/repositories/magnolia /opt/magnolia/data/workspaces \
    && mkdir -p /opt/magnolia/modules \
    && chmod 777 -R /etc/magnolia/config && chmod o+t -R /etc/magnolia/config \
    && chmod 777 -R /opt/magnolia/data   && chmod o+t -R /opt/magnolia/data \
    && chmod 777 -R /opt/magnolia/modules && chmod o+t -R /opt/magnolia/modules

# Download and extract Magnolia Community WAR
RUN mkdir -p /usr/local/tomcat/webapps/ROOT \
    && curl -fsSL "$MAGNOLIA_WAR_URL" -o /tmp/magnolia.war \
    && cd /usr/local/tomcat/webapps/ROOT && jar -xf /tmp/magnolia.war \
    && rm /tmp/magnolia.war

# Download PostgreSQL JDBC driver
RUN curl -fsSL "$POSTGRESQL_JAR_URL" -o /usr/local/tomcat/lib/postgresql.jar

# RUDI Magnolia module (templates FTL, définitions YAML, REST endpoints)
COPY modules-rudi /opt/magnolia/modules/rudi

COPY server.xml /usr/local/tomcat/conf/server.xml

ENV CATALINA_OPTS="-Xmx2048m -Dmagnolia.update.auto=true"
