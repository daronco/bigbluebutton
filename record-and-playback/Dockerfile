FROM ubuntu:16.04

RUN apt-get update && apt-get install -y wget

RUN wget http://ubuntu.bigbluebutton.org/repo/bigbluebutton.asc -O- | apt-key add -
RUN echo "deb http://ubuntu.bigbluebutton.org/xenial-110/ bigbluebutton-xenial main" | tee /etc/apt/sources.list.d/bigbluebutton.list
RUN apt-get update

RUN apt-get install -y ffmpeg=7:2.8.11-0ubuntu0.16.04.1 ruby2.3
RUN apt-get install -y bbb-record-core bbb-playback-presentation poppler-utils imagemagick

ENV     app /usr/local/bigbluebutton/core/scripts
WORKDIR $app
COPY    wait-and-process.rb $app/

# Copy the local scripts in case we have customizations over the packaged version
COPY    ./core/scripts/ $app/

CMD        ["ruby", "wait-and-process.rb"]
