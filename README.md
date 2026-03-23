# Minecraft Docker Server

This project is a small minecraft server built in a small docker container based on Ubuntu. The image can be run on any system with a docker daemon installed.

## Requirements

To use this project you must have a docker daemon installed on the destination host.

### To build:
```bash
  docker build -t minecraft-server -f Dockerfile .
```

### To compose:
Make sure that a .env file has been created in the root of this project with the following variables set:
* DOCKERDATA - this is the location you want your world data to be stored in on your host machine.
* PORT - The port to expose the minecraft server on, on the host.
* SERVER_NAME - A unique name for the server so it stores multiple minecraft servers separately.

```bash
  docker-compose up -d
```
## License

[The Unlicense](https://unlicense.org)