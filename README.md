# ytbu
#### Automatically backup your youtube subscription's videos.
Supports webhook notifications for OAuth token refresh. Main code in bash, API retrived with python, downloads with [youtube-dl](https://github.com/rg3/youtube-dl).

### Setup:
ytbu is meant to run on linux, with [crontab](https://www.ostechnix.com/a-beginners-guide-to-cron-jobs/). ([timing guide](https://crontab.guru/))
Cron should execute [ytbu.sh](ytbu.sh)

See [ytbu.sh](ytbu.sh) for more instructions and for the main config.
Also edit [ytbu_getdata.py](ytbu_getdata.py) to set the working directory for it aswell and set up webhooks for token refresh notifications.

youtube-dl may be configured at the bottom of [ytbu.sh](ytbu.sh)
