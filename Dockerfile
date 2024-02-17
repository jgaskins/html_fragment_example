FROM 84codes/crystal:1.11.2-alpine AS build

WORKDIR /build
COPY shard.yml shard.lock .
RUN shards install -j12

COPY src/ src/
COPY views/ views/

RUN shards build --static --release

FROM alpine

WORKDIR /app
COPY --from=build /build/bin/html_fragment_example /app

CMD ["/app/html_fragment_example"]
