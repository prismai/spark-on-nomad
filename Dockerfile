ARG base_image=python:3.8.5-alpine3.12

# hadolint ignore=DL3006
FROM ${base_image} as builder

# hadolint ignore=DL3018
RUN apk add --no-cache alpine-sdk
COPY k8s-emul/requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt && pip check
RUN find /usr/local

# hadolint ignore=DL3006
FROM ${base_image}

# hadolint ignore=DL3018
RUN apk add --no-cache libstdc++
COPY --from=builder /usr/local /usr/local

WORKDIR /app
COPY k8s-emul/* ./
RUN rm requirements.txt

CMD ["python", "server.py"]
