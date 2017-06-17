FROM ubuntu:16.04

RUN apt-get update && apt-get install -y wget

RUN wget http://ubuntu.bigbluebutton.org/repo/bigbluebutton.asc -O- | apt-key add -
RUN echo "deb http://ubuntu.bigbluebutton.org/xenial-110/ bigbluebutton-xenial main" | tee /etc/apt/sources.list.d/bigbluebutton.list
RUN apt-get update

RUN apt-get install -y ffmpeg=7:2.8.11-0ubuntu0.16.04.1 ruby2.3

# poppler-utils and imagemagick are missing from bbb packages
RUN apt-get install -y bbb-record-core bbb-playback-presentation poppler-utils imagemagick

ENV     app /usr/local/bigbluebutton/core/resque-docker
WORKDIR $app

# Copy the local scripts over the packaged ones
COPY ./core/ $app/../

RUN bundle install

ENV QUEUE recordings:process
ENV VVERBOSE 1
CMD ["./resque-worker-wrapper.sh", "rake", "resque:work"]

# ruby script that listens to redis
# COPY wait-and-process.rb $app/
# CMD  ["ruby", "wait-and-process.rb"]
