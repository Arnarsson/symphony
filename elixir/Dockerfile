# Stage 1: Build
FROM hexpm/elixir:1.19.0-erlang-28.0-alpine-3.21.3 AS build

RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN mix compile && \
    mix release symphony

# Stage 2: Runtime
FROM alpine:3.21.3 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses-libs git openssh-client

WORKDIR /app

ENV MIX_ENV=prod
ENV SYMPHONY_DATABASE_PATH=/data/symphony.db

COPY --from=build /app/_build/prod/rel/symphony ./

RUN mkdir -p /data

VOLUME ["/data"]

EXPOSE 8080

ENTRYPOINT ["bin/symphony"]
CMD ["start"]
