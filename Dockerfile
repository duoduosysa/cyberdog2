# Copyright (c) 2023 Beijing Xiaomi Mobile Software Co., Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM arm64v8/ubuntu:bionic
ENV CMAKE_VER="3.21.2"
ENV GITHUB_URL="github.com"
ENV GITHUB_RAW="raw.githubusercontent.com"

WORKDIR /home/builder

# copy all local dependency archives into the build context
COPY config-deb.tar.gz .
COPY base-deb.tar.gz .
COPY carpo-ros2-debs.tgz .
COPY docker-depend.tar.gz .

# switch to Tsinghua mirror FIRST (much faster in China)
RUN mv /etc/apt/sources.list /etc/apt/sources.list.bak && \
  echo "deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic main restricted universe multiverse" > /etc/apt/sources.list && \
  echo "deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
  echo "deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic-backports main restricted universe multiverse" >> /etc/apt/sources.list && \
  echo "deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic-security main restricted universe multiverse" >> /etc/apt/sources.list

# install ca-certificates + tzdata from local archive
RUN apt-get update \
&& apt-get install -q -y --no-install-recommends wget \
&& tar -xzvf config-deb.tar.gz \
&& dpkg -i config-deb/ca-certificates/*.deb \
&& echo 'Etc/UTC' > /etc/timezone \
&& ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime \
&& dpkg -i config-deb/tzdata/*.deb \
&& rm -rf config-deb config-deb.tar.gz /var/lib/apt/lists/*

# setup environment
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV DEBIAN_FRONTEND noninteractive

# install base packages from local archive
RUN apt-get update \
&& tar -xzvf base-deb.tar.gz \
&& cp base-deb/*.deb /var/cache/apt/archives/ \
&& apt install --no-install-recommends -y --allow-downgrades /var/cache/apt/archives/*.deb \
&& rm -rf base-deb base-deb.tar.gz /var/lib/apt/lists/*

# change pip mirror (replace one near you)
RUN pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple pip -U \
&& pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

RUN echo "deb [trusted=yes] https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu/ bionic main" > /etc/apt/sources.list.d/ros2-latest.list

# install ROS2 Galactic from local archive
RUN mkdir -p /opt/nvidia/l4t-packages/ \
&& touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall

RUN mkdir carpo-ros2-debs \
&& tar -xf carpo-ros2-debs.tgz -C carpo-ros2-debs \
&& (dpkg -i carpo-ros2-debs/*.deb || true) \
&& apt-get update && apt-get install -f -y --allow-downgrades \
&& rm -rf carpo-ros2-debs carpo-ros2-debs.tgz

# install docker dependencies from local archive (split into steps for caching)
RUN tar -xzvf docker-depend.tar.gz && rm -f docker-depend.tar.gz

RUN dpkg --force-overwrite -i docker-depend/dpkg-deb/*.deb || true

RUN apt-get update \
&& cp docker-depend/apt-deb/*.deb /var/cache/apt/archives/ \
&& apt install --no-install-recommends -y --allow-downgrades --fix-broken /var/cache/apt/archives/*.deb

RUN apt-get install -y python3-netifaces \
&& grep -v netifaces ./docker-depend/whls/requirement.txt > /tmp/req_filtered.txt \
&& python3 -m pip install --no-index --find-link ./docker-depend/whls/ -r /tmp/req_filtered.txt --ignore-installed

RUN cp docker-depend/config-file/libwebrtc.a /usr/local/lib \
&& cp docker-depend/config-file/libgalaxy-fds-sdk-cpp.a /usr/local/lib/ \
&& cp -r docker-depend/config-file/webrtc_headers/ /usr/local/include/ \
&& cp -r docker-depend/config-file/include/* /usr/local/include/ \
&& cp -r docker-depend/config-file/grpc-archive/* /usr/local/lib/ \
&& cp docker-depend/config-file/ldconf/* /etc/ld.so.conf.d \
&& ldconfig \
&& rm -rf docker-depend

RUN rm -f /usr/bin/python \
&& ln -s /usr/bin/python3 /usr/bin/python \
&& chown -R root:root /opt/ros2/cyberdog \
&& chown -R root:root /opt/ros2/galactic

# set ros 2 environment configs
RUN echo "ros2_galactic_on(){" >> /root/.bashrc && \
  echo "export ROS_VERSION=2" >> /root/.bashrc && \
  echo "export ROS_PYTHON_VERSION=3" >> /root/.bashrc && \
  echo "export ROS_DISTRO=galactic" >> /root/.bashrc && \
  echo "source /opt/ros2/galactic/setup.bash" >> /root/.bashrc && \
  echo "}" >> /root/.bashrc

CMD ["bash"]
