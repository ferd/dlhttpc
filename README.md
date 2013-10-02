dlhttpc
=======

Purpose
-------
dlhttpc is a fork of https://github.com/ferd/lhttpc, which is itself a fork of Erlang Solution's lhttpc.

The main objective of dlhttpc is to provide a good HTTP client for use cases where many (and I do mean many) requests are sent to a restricted number of domains, over long-lived TCP connections.

How it works
------------

dlhttpc works similarly to lhttpc, but with the difference that for each endpoint (domain/ip + port + ssl) of requests, a load balancer is started allowing as many connections as mentioned in the configuration.

Each load balancer has N workers that will connect on-demand to each client.

The load balancer/pools/dispatcher mechanism is based on [dispcount](https://github.com/ferd/dispcount), which will randomly contact workers. This means that even though few connections might be required, the nondeterministic dispatching may make all connections open at some point. As such, dlhttpc should be used in cases where the load is somewhat predictable in terms of base levels.

When to use dlhttpc
-------------------

Whenever the HTTP client you're currently using happens to block trying to access resources that are too scarce for the load required, you may experience something similar to bufferbloat, where the queuing up of requests ends up ruining latency for everyone, making the overall response time terribly slow.

In the case of Erlang, this may happen over pools that dispatch resources through message passing. Then the process' mailbox ends up as a bottleneck that makes the application too slow. Dispcount was developed to solve similar issues by avoiding all message passing on busy workers, and is used as the core dispatcher of dlhttpc to join the flexibility of lhttpc to the overload resilience of dispcount.

Configuration
-------------

The following variables must be defined:

- `restart`: restart value for the pool
- `shutdown`: shutdown time for the pool
- `maxr`: max amount of restart for workers from the pool
- `maxt`: max time (in seconds) as a period given for workers of the pool.

Warning
-------
This is a beta version of the library, still being tested.

Dispcount registers a process for each of the pools started. This sadly means that each endpoint (host + port + ssl) will register its own process. This is annoying, but shouldn't matter too much given the use case for dlhttpc is for many requests to few endpoints.

Todo
----

- Find a mechanism to shut down inactive pools.
- Fix application behaviour to allow orderly shutdown, including pools.
- Reduce the system load in case of endpoints going offline by having a connection monitor.
- Fix tests. They were ported mostly directly from lhttpc, and dlhttpc was tested in the realm of private projects. Tests should be made available to a greater public.
- Document how to use things better. Right now usage is 'similar to whatever lhttpc was'
