# Tarantool replication conflicts test example

## Description

Simple example of how to test Tarantool replication conflicts using Tarantool Cartridge test-helpers: https://www.tarantool.io/en/doc/latest/book/cartridge/cartridge_api/modules/cartridge.test-helpers/

Code based on https://github.com/tarantool/examples/tree/master/profile-storage

By default this example has so called "replication resolve trigger" https://github.com/no1seman/replication_conflict/blob/3ba3e71daf991c7f80c6c4a54caa46972f8097e5/init.lua#L65 present and application passes all tests, but if you will comment 65-73 lines in init.lua and run test suite once again you will get an error.

ATTENTION!!! Do not use my_trigger() function code in real applications. It's only for test purposes. Using this particular algorithm will lead to data inconsistency. In real applications you have to use more complicated algorithms based on external facts: external sequences, external timestamp and so on. 

## How to run this example

1. Clone repository
2. Go to root of repository
3. Run: cartridge build
4. Run: ./deps.sh
5. Run: .rocks/bin/luatest -c

