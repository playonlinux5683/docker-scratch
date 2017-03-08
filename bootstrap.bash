#! /bin/bash

ENVFILE=.env
function wrapCall {
	local func="$1"
	shift
	echo "$func: begin"
	$func $@
	echo "$func: end"
}

function prompt {
	local callback=$1
	local variable=$1
	local responses=("Yes" "No" "Back" "Exit")

	echo "Command $1 is a dependency of command $2."
	echo "Do you want this dependency to be executed ?"

	select response in ${responses[@]}; do
		case $response in
			Yes )
				eval "$variable"=true
				wrapCall $callback
				break
			;;
			Back )
				wrapCall entrypoint
			;;
			Exit )
				exit;
			;;
		esac
	done
}

function run {
	local script="$1"

	local containers=($(docker ps --format {{.Names}} | grep "${COMPOSE_PROJECT_NAME}"))

	for container in "${containers[@]}"
	do
		isUp=$(docker inspect -f {{.State.Running}} ${container})
		until $isUp ; do
			>&2 echo "Container ${container} is unavailable - sleeping"
			sleep 1
			isUp=$(docker inspect -f {{.State.Running}} ${container})
		done
		>&2 echo "Container ${container} is up - executing command"

		docker exec -it ${container} bash -c "$script"
	done;
}

function unconfigure {
	run "/unconfigure.sh"
}

function stop {
	[ -z "$unconfigure" ] && {
		prompt 'unconfigure' 'stop'
	}
	local running=$(docker ps -a -q  | grep "${COMPOSE_PROJECT_NAME}")
	[ ! -z "$running" ] && {
		docker rm $running -f
	} || {
		echo "Nothing to do"
	}
}

function purge {
	[ -z "$stop" ] && {
		prompt 'stop' 'purge'
	}
	local images=$(docker images -q "${COMPOSE_PROJECT_NAME}*")
	[ ! -z "$images" ] && {
		docker rmi $images -f
	} || {
		echo "Nothing to do"
	}
}

function build {
	docker-compose build
}

function start {
	[ -z "$build" ] && {
		prompt 'build' 'start'
	}
	docker-compose up -d --build --force-recreate
}

function configure {
	[ -z "$start" ] && {
		prompt 'start' 'configure'
	}
	run "/configure.sh"
}

function ps {
	docker ps --format {{.Names}} | grep "${COMPOSE_PROJECT_NAME}"
}

function psi {
	docker images -f reference="${COMPOSE_PROJECT_NAME}*"
}

function help {
	local script=$(basename $0)
	cat <<-EOF
	Usage: $script
		Script for managing operations on containers which prompt a list of availables commands:
		        unconfigure => Ask started containers to execute 'unconfigure.sh' script in itselves
		        stop => Stop all started containers
		        purge => Remove all images in cache
		        build => Build all custom images
		        start => Start all containers
		        configure => Ask started containers to execute 'configure.sh' script in itselves
						ps => list all containers
						psi => list all images
						help => Show this help
						exit => Exit the program
	EOF
}

################################################################################
# Commands:
# - unconfigure:
#		-> Ask started containers to execute 'unconfigure.sh' script in itselves
# - stop:
#		-> Stop all started containers
# - purge:
#		-> Remove all images in cache
# - build:
#		-> Build all custom images
# - start:
#		-> Start all containers
# - configure:
#		-> Ask started containers to execute 'configure.sh' script in itselves
# - ps:
#		-> List all containers
# - psi:
#		-> List all images
# - help:
#		-> Show this help
# - exit:
#		-> Exit the program
################################################################################

function entrypoint {
	echo 'Welcome'
	. $ENVFILE
	echo ${COMPOSE_PROJECT_NAME}
	[ ! -z "$1" ] && {
		wrapCall "$1"
	} || {

		local commands=("unconfigure" "stop" "purge" "build" "start" "configure" "help" "ps" "psi" "exit")
		local isFinished=false

		until $isFinished; do
			echo "Choose your action"

			select cmd in "${commands[@]}"; do
				case $cmd in
					unconfigure | stop | purge | build | start | configure | ps | psi | help )
					break
					;;
					exit )
						isFinished=true
						break
					;;
				esac
			done
			[ $isFinished == false ] && {
				action=$cmd
				eval "$action"=true
				wrapCall $cmd
			}
		done
	}

	echo 'Good bye'
}

entrypoint $@
