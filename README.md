# JAliEn Startup Scripts

This repository contains the scripts required to control CE and MonaLisa services in VOBoxes. The scripts will reside in `/cvmfs/alice.cern.ch/scripts/vobox`

# Usage
``` 
Usage: jalien-vobox <Command> [<Service>]

<Command> is one of: start status stop restart mlstatus

<Service> is one of: ce monalisa (defaulting to both if not specified)
```

Running a command without specifying a service will run the command on both CE and MonaLisa services.

## Configuration
Both the services are able to start without any configurations. However, following parameters can be overriden by defining them in `$HOME/alien/version.properties` as key-value pairs.

```
MONALISA_HOME=<MonaLisa package location>
MONALISA=<MonaLisa version>
JALIEN=<JAliEn version>
```
> Note: As the MonaLisa package is not available in CVMFS yet, it is essential to define MONALISA_HOME to specify the MonaLisa package location. If it is not locally available, please use `install` as the value for `<MonaLisa package location>`.

If it is required to run any shell command before starting either of the services, they can be added in `$logDir/ml-env.sh` or `$logDir/ce-env.sh`. Content in these two scripts will be run before starting the service. `logDir` will default to `$HOME/ALICE/alien-logs` if a `LOGDIR` is not defined in LDAP. 
