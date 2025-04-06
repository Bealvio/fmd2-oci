# FMD2

## Descriptions

Dockerized FMD2 (Windows with Wine) using VNC, noVNC and webSocketify to display GUI on a webpage.

<https://github.com/dazedcat19/FMD2>

Make sure to configure it using the 'web' ui.

## Features

- Does not require any display, works headless
- Keeps all of FMD2 features
- Since it's docker, it works on Linux

## Docker

```yaml
---
version: '3'
services:
  fmd2:
    image: zot.bealv.io/public/fmd2-nix:v2.0.34.5
    container_name: fmd2
    ports:
      - 6080:6080
    volumes:
      - ./wine:/home/fmd2/.wine
      - ./data:/app/FMD2/data
      - ./userdata:/app/FMD2/userdata
      - ./downloads:/app/FMD2/downloads
    restart: unless-stopped
```

## License

[MIT](https://choosealicense.com/licenses/mit/)
