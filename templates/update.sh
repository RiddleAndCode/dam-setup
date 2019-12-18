#!/usr/bin/env sh

docker login
%DOCKER_COMPOSE_LOC% --no-ansi -f %DOCKER_COMPOSE_FILE% pull
docker logout
