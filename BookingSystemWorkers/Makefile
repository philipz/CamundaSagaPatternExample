NAME = bookhotel
APP_NAME = BookHotel.js
NODE_VERSION = 16-alpine

PWD := $(shell pwd)

.PHONY: all

all: build

build:
	docker run -ti --rm -v $(PWD):/app node:$(NODE_VERSION) /app/compile.sh $(APP_NAME) $(NAME)
	echo 'FROM scratch\nADD build.tar.gz /\nCMD ["/$(NAME)"]' > Dockerfile
	docker build -t philipz/$(NAME) .
	rm build.tar.gz Dockerfile

clean: clean-docker

clean-docker:
	docker rmi philipz/$(NAME)
