# ptv-bash-pid
Generates a Passenger Information Display from the PTV API using jq and bash

You'll need the following installed:

- jq
- openssl
- coreutils

If you encounter issues with jq, it's possibly because you're using an outdated version. Get the latest from [here](https://stedolan.github.io/jq/).

I also had trouble getting older versions of GNU date to play with ISO 8601 dates. Update to latest coreutils if it spits fire.
