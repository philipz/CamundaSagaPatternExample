NAME = bookhotel
APP_NAME = BookHotel.js
NODE_VERSION = 18-alpine

PWD := $(shell pwd)

.PHONY: all

all: build

build:
	docker run -ti --rm -v $(PWD):/app node:$(NODE_VERSION) /app/compile.sh $(APP_NAME) $(NAME)
	echo 'FROM scratch\nADD build.tar.gz /\nCMD ["/$(NAME)"]' > Dockerfile
	docker buildx build --platform linux/amd64,linux/arm64 -t philipz/$(NAME) --push .
	rm -f build.tar.gz Dockerfile

clean: clean-docker

clean-docker:
	docker rmi philipz/$(NAME)
