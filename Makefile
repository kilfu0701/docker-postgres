current_branch := $(shell git rev-parse --abbrev-ref HEAD)

build:
	docker buildx build --platform linux/amd64,linux/arm64,linux/amd64/v2 -t kilfu0701/postgres:$(current_branch) -f Dockerfile .

config:
	docker-compose --env-file .env config
