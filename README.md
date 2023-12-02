# ShieldWall - Controller

Setup-Scripts and library to run a controller that is able to manage multiple [ShieldWall Boxes](https://github.com/shield-wall-net/box)

ShieldWall firewalls are designed to be managed centrally by their linked controller.

Controllers are self-hosted.

## WARNING: Development still in progress!

----

## Roadmap

- [ ] Web UI
  - [ ] Configuration
    - [ ] Boxes
    - [ ] Controller
- [ ] Box Management
  - [ ] Get Information from Boxes
    - [ ] IS vs SHOULD-BE - Package & Config Versioning
  - [ ] Patch/Package management
  - [ ] Configuration rollout
- [ ] Logging
  - [x] Boxes => Rsyslog-TLS => Controller => [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) => [Grafana Loki](https://grafana.com/docs/loki/latest/get-started/overview)
  - [ ] [Visualize/Log Analysis](https://grafana.com/docs/loki/latest/visualize/grafana/)
    - [ ] GeoIP Integration
    - [ ] Collection of Dashboards
  - [ ] [Alerting](https://grafana.com/docs/loki/latest/alert/)
  - [ ] NetFlow collection using SoftFlowd, [GoFlow2](https://github.com/netsampler/goflow2) and Loki/Grafana

----

## Setup

Designed to run on:
* [Debian 12 netinstall](https://www.debian.org/CD/netinst/)
* no Desktop environment (*GUI*)
* installed without `standard system utilities`

You may want to use LVM and use partitioning like this:

```bash
/sda
- /sda1 => ext4 /boot (512 MB)
- /sda2 => LVM

vg0
- lv1 => ext4 / (min 10 GB)
- lv2 => ext4 /var (min 20 GB)
- lv3 => swap (min 1 GB)
```

### Why Debian?

The config can be ported later on - but we need to start somewhere.
