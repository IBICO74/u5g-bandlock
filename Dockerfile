FROM alpine:3.20

RUN apk add --no-cache bash curl jq openssh-client sshpass

WORKDIR /app
COPY apply.sh loop.sh ./
RUN chmod +x apply.sh loop.sh

# No env file inside the image — pass config as environment variables.
ENV U5G_BANDLOCK_ENV=/dev/null

ENTRYPOINT ["/app/loop.sh"]
