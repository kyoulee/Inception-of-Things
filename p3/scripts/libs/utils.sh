#!/bin/bash

log_info() { echo -e "\e[32m[INFO]\e[0m $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }
