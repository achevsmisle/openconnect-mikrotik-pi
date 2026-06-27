DOCKER_ID=achevsmisle
IMAGE_NAME:=openconnect-mikrotik-pi
IMAGE_VERSION?=1.5

.PHONY: install_qemu mikrotik arm64 amd64 full_build

install_qemu:
	docker run --privileged --rm tonistiigi/binfmt --install all

mikrotik:
	docker buildx build -t "${DOCKER_ID}/${IMAGE_NAME}:${IMAGE_VERSION}" -t "${DOCKER_ID}/${IMAGE_NAME}:latest" --platform linux/arm/v7 .

arm64:
	docker buildx build -t "${DOCKER_ID}/${IMAGE_NAME}:${IMAGE_VERSION}" -t "${DOCKER_ID}/${IMAGE_NAME}:latest" --platform linux/arm64/v8 .

amd64:
	docker buildx build -t "${DOCKER_ID}/${IMAGE_NAME}:${IMAGE_VERSION}" -t "${DOCKER_ID}/${IMAGE_NAME}:latest" --platform linux/amd64 .

full_build_push:
	docker buildx build -t "${DOCKER_ID}/${IMAGE_NAME}:${IMAGE_VERSION}" -t "${DOCKER_ID}/${IMAGE_NAME}:latest" --platform linux/amd64,linux/arm/v7,linux/arm64/v8 --push .

full_build_push_test:
	docker buildx build -t "${DOCKER_ID}/${IMAGE_NAME}:${IMAGE_VERSION}-test" --platform linux/amd64,linux/arm/v7,linux/arm64/v8 --push .
