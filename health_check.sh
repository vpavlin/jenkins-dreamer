#!/usr/bin/bash

set -e

ps aux | grep -v grep | grep "/opt/jenkins-dreamer/dreamer.sh"