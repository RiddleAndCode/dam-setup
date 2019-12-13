#!/usr/bin/env sh

%DOCKER_COMPOSE_LOC% --no-ansi -f %DOCKER_COMPOSE_FILE% pull
%DOCKER_COMPOSE_LOC% --no-ansi -f %DOCKER_COMPOSE_FILE% up
