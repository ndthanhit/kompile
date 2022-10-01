ARG OS=centos
ARG OS_VERSION=7
FROM ${OS}:${OS_VERSION} as builder
LABEL org.opencontainers.image.source="https://github.com/KonduitAI/kompile"
RUN yum -y install wget  && wget https://github.com/graalvm/graalvm-ce-dev-builds/releases/download/22.3.0-dev-20220915_2039/graalvm-ce-java11-linux-amd64-dev.tar.gz && tar xvf graalvm-ce-java11-linux-amd64-dev.tar.gz && mv graalvm-ce-java11-22.3.0-dev/ /usr/java

ENV JAVA_HOME=/usr/java/
ENV GRAALVM_HOME=/usr/java/
RUN yum -y install git gcc gcc-c++ zlib* xz make openssl openssl-devel
RUN         curl -fsSL http://cmake.org/files/v3.19/cmake-3.19.0.tar.gz | tar xz && cd cmake-3.19.0 && \
                              ./configure --prefix=/opt/cmake && make -j2 && make install && cd .. && rm -r cmake-3.19.0
RUN yum -y group install "Development Tools" && yum -y update
ENV PATH=/opt/cmake/bin:${PATH}
RUN /usr/java/bin/gu install native-image
RUN mkdir /kompile
RUN curl https://dlcdn.apache.org/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz --output /kompile/mvn.tar.gz
RUN cd /kompile/ && tar xvf mvn.tar.gz && mv apache-maven-3.8.6 mvn
ENV PATH="/kompile/mvn/bin/:/root/.kompile/python/bin/:${PATH}:/usr/java/bin/"
ARG BACKEND_PROFILE=cpu
ARG JAVCPP_PLATFORM=linux-x86_64
ARG DL4J_BACKEND=1.0.0-SNAPSHOT
ARG LTO=OFF
RUN yum install -y centos-release-scl
RUN yum install -y devtoolset-9
RUN echo "source /opt/rh/devtoolset-9/enable" >> /etc/bashrc
SHELL ["/bin/bash", "--login", "-c"]
RUN cd /kompile && git clone  https://github.com/deeplearning4j/deeplearning4j && \
    cd /kompile/deeplearning4j && cd libnd4j && mvn -P${BACKEND_PROFILE} -Dlibnd4j.lto=${LTO} -Djavacpp.platform=${JAVCPP_PLATFORM}  install -Dmaven.test.skip=true && \
    cd /kompile/deeplearning4j && cd nd4j && mvn -P${BACKEND_PROFILE} -Djavacpp.platform=${JAVCPP_PLATFORM}  install -Dmaven.test.skip=true && \cd /kompile/deeplearning4j && cd nd4j && mvn -P${BACKEND_PROFILE} -Djavacpp.platform=${JAVCPP_PLATFORM}  install -Dmaven.test.skip=true && \
    cd /kompile/deeplearning4j && cd datavec && mvn -Djavacpp.platform=${JAVCPP_PLATFORM} install -Dmaven.test.skip=true && \
    cd /kompile/deeplearning4j && cd python4j && mvn -Djavacpp.platform=${JAVCPP_PLATFORM}  install -Dmaven.test.skip=true && \
    cd /kompile/deeplearning4j && cd deeplearning4j && mvn -pl :deeplearning4j-modelimport   install -Dmaven.test.skip=true --also-make -Djavacpp.platform=linux-x86_64 && \
    cd /kompile && git clone https://github.com/KonduitAI/konduit-serving  && \
    cd /kompile/konduit-serving && mvn -Ddl4j.version=1.0.0-SNAPSHOT -Djavacpp.platform=${JAVCPP_PLATFORM} -Dchip=cpu clean install -Dmaven.test.skip=true

COPY ./kompile-c-library /kompile/kompile-c-library
COPY ./kompile-python /kompile/kompile-python
COPY ./src /kompile/src
ENV KOMPILE_PREFIX=/kompile
COPY pom.xml /kompile/pom.xml
RUN cd /kompile && mvn -Djavacpp.platform=linux-x86_64 -Pnative clean package -Dmaven.test.skip=true &&\
        mv /kompile/target/kompile /kompile && \
        chmod +x /kompile/kompile && \
        rm -rf /kompile/deeplearning4j /kompile/konduit-serving && \
         chmod -R 755 /kompile && \
        rm -rf /root/* && \
         rm -rf /kompile/mvn \
                   /kompile/mvn.tar.gz \
                  /kompile/miniconda3 \
                  /kompile/miniconda3.sh \
                  /kompile/target \
                  /root/.javacpp \
                  /root/.conda \
                  /root/.m2 \
                  /kompile/src \
                  /kompile/pom.xml


FROM ${OS}:${OS_VERSION}
RUN mkdir /kompile && yum -y install sed findutils
COPY --from=builder /kompile/kompile /kompile/kompile
COPY --from=builder /kompile/kompile-c-library /kompile/kompile-c-library
COPY --from=builder /kompile/kompile-python /kompile/kompile-python
COPY   /src/main/resources/META-INF/native-image /kompile/native-image
ENV JAVA_HOME=/root/.kompile/graalvm
RUN yum -y install git gcc gcc-c++ zlib zlib-devel xz  freetype freetype-devel
RUN /kompile/kompile install install-tool --programName=cmake
ENV PATH="/root/.kompile/mvn/bin/:/root/.kompile/python/bin/:${PATH}:/usr/java/bin/:/root/.kompile/graalvm/bin"
ENTRYPOINT ["/kompile/kompile"]