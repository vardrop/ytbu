#!/bin/bash
# saner programming env: these switches turn some bugs into errors
set -o errexit -o pipefail -o noclobber -o nounset
##############################LOCK FILE############################## https://stackoverflow.com/a/25243837/7157385
SCRIPTNAME=$(basename $0)
LOCKDIR="/var/lock/${SCRIPTNAME}"
PIDFILE="${LOCKDIR}/pid"

if ! mkdir $LOCKDIR 2>/dev/null
then
    # lock failed, but check for stale one by checking if the PID is really existing
    PID=$(cat $PIDFILE)
    if ! kill -0 $PID 2>/dev/null
    then
       echo "Removing stale lock of nonexistent PID ${PID}" >&2
       rm -rf $LOCKDIR
       echo "Restarting myself (${SCRIPTNAME})" >&2
       exec "$0" "$@"
    fi
    echo "$SCRIPTNAME is already running, bailing out" >&2
    exit 1
else
    # lock successfully acquired, save PID
    echo $$ > $PIDFILE
fi

trap "rm -rf ${LOCKDIR}" QUIT INT TERM EXIT
##############################FUNCTIONS##############################
ytbu_err() { # any error and help ends here
  printf '%s\n' \
    "Normal usage: 'bash ytbu.sh'" \
    "Quickstart: 'sudo bash ytbu.sh go'" \
    "Only install dependencies: 'bash ytbu.sh install'" \
    "Only configure: 'bash ytbu.sh config'" \
    "Run normally: 'bash ytbu.sh'" \
    "Guide for retriving your client_secret.json: 'bash ytbu.sh secret'" \
    "For more information about configuration see https://github.com/pyptq/ytbu"
  exit 1
}
ytbu_secret() { # just a guide for setup
  printf '%s\n' \
    "To retrive your client_secret.json open:" \
    "https://console.developers.google.com/apis/credentials?project=_" \
    "If you don't have one, create a project." \
    "Under APIs enable Youtube Data APIv3." \
    "Go to credentials page under APIs & Services." \
    "Ensure, that at the top left your project is selected." \
    "Click on 'OAuth consent screen' in the top bar, enter a name and at the bottom, click Save." \
    "Again on the Credentials screen press 'Create credentials', 'OAuth client ID', 'Other'" \
    "Enter a name for the backup app, click 'Create'." \
    "You will be presented with your client ID and your client secret. Close that." \
    "Under 'OAuth 2.0 client IDs' you will find the client you just created." \
    "On the far right there is a download button. Click that." \
    "Rename the downloaded file to client_secret.json and move it to ytbu's working directory."
}
test_sudo() {
  if ! command -v sudo>/dev/null; then
    echo "ERR: You need root to install dependencies!"
    ytbu_err
  fi
} # id.ee
ytbu_install() {
  test_sudo #check for sudo (code from id.ee)
  sudo apt update
  sudo apt install ffmpeg python3 python3-pip curl wget -y
  #Download youtube-dl
  sudo curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/local/bin/youtube-dl
  #Mark youtube-dl executable
  sudo chmod a+rx /usr/local/bin/youtube-dl
  # Install python script dependencies
  sudo pip3 install --upgrade google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 oauth2client
  echo Dependencies installed!
}
datamonster () {
#Repetitive checking needs less code when using functions
#get subscriptions from google, using python version as it was the fastest (and only) I could get working with the API
$py3 $wdir/ytbu_getdata.py --noauth_local_webserver | tee $wdir/.ytbu_tmp_data.txt
#filter newest data and append to the channel list
cat $wdir/.ytbu_tmp_data.txt | grep -o "'channelId': '[a-zA-Z0-9_-]*" | sed "s#^.*'#https://www.youtube.com/channel/#" | grep -v $ownid >> $wdir/.ytbu_channels.txt
# Check if there is any more pages (checks if there is a token for next page) (api can get only 50 subscriptions once)
checknextempty=$(cat $wdir/.ytbu_tmp_data.txt | grep -o "'nextPageToken': '[a-zA-Z0-9_-]*" | sed "s#^.*'##" )
}
ytbu_channelsget(){
  $py3 ytbu_getownid.py | tee $wdir/.ytbu_tmp_ownid
  ownid=$(cat $wdir/.ytbu_tmp_ownid | grep -o "'id': '[a-zA-Z0-9_-]*" | sed "s#^.*'##")
  datamonster #get data
  while ! [ "$checknextempty" = "" ]; do # if you have more than 50 subscribed
  cat $wdir/.ytbu_tmp_data.txt | grep -o "'nextPageToken': '[a-zA-Z0-9_-]*" | sed "s#^.*'##" | sed -e "s@^@nextpagevar='@" -e "s@\$@'@" > $wdir/.ytbu_tmp_nextpager.py # give next page token to python
  datamonster # get more data
done # and loop if there is even more data
}
ytbu_config_wdir(){
  reader=1
  while [[ $reader == 1 ]]; do
    wdir=$PWD
    echo Current working directory is $wdir
    read -p "Change it? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      read -p "What do you want to change it to? (full directory path, DO NOT END WITH A SLASH!): " -r
      wdir=$REPLY
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      reader=0
    else
      echo What?
      reader=1
    fi
  done
}
ytbu_config_webhooky(){
  reader=1
  while [[ $reader == 1 ]]; do
    read -p "Use webhooks to notify: OAuth token expired ? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_oauth=1
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_oauth=0
      reader=0
    else
      echo What?
      reader=1
    fi
  done
  reader=1
  while [[ $reader == 1 ]]; do
    read -p "Use webhooks to notify: ytbu run completed ? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_complete=1
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_complete=0
      reader=0
    else
      echo What?
      reader=1
    fi
  done
  if [[ "$webhooky_oauth" = 1 ]] || [[ $webhooky_complete = 1 ]]; then #
    read -p "Enter an url to make a post request to: " -r
    webhooky_token=$REPLY
  else
    :
  fi
}
ytbu_config_installcheck(){
  #set defaults
  py3="/usr/bin/python3"
  ydl="/usr/local/bin/youtube-dl"
  reader=1
  while [[ $reader == 1 ]]; do
    if $py3 --version; then #check if default works
      reader=0
    else
      echo python3 not detected/installed!
      echo r - retry, check again
      echo c - change path to python3
      echo x - exit
      echo
      echo If you see something with /bin/python, change the path to it:
      whereis python3 #look for python3
      read -p "" -n 1 -r
      echo
      replyz=$REPLY #changing reply, since it will be overwritten when changing path
      if [[ $replyz =~ ^[Rr]$ ]]; then
        :#retry
        readerz=1
      elif [[ $replyz =~ ^[Cc]$ ]]; then
        read -p "full path to python3: " -r #change path
        py3=$REPLY
        readerz=1
      elif [[ $replyz =~ ^[Xx]$ ]]; then
        echo ERR: python3 not detected!
        ytbu_err
      else
        echo What?
        readerz=1
      fi
      reader=1
    fi
  done
  reader=1 #once again, but for youtube-dl instead of python3
  while [[ $reader == 1 ]]; do
    if $ydl --version; then
      reader=0
    else
      echo youtube-dl not detected/installed!
      echo r - retry, check again
      echo c - change path to python3
      echo x - exit
      echo
      echo If you see something with /bin/youtube-dl, change the path to it:
      whereis youtube-dl
      read -p "" -n 1 -r
      echo
      replyz=$REPLY
      if [[ $replyz =~ ^[Rr]$ ]]; then
        :
        readerz=1
      elif [[ $replyz =~ ^[Cc]$ ]]; then
        read -p "full path to youtube-dl: " -r
        py3=$REPLY
        readerz=1
      elif [[ $replyz =~ ^[Xx]$ ]]; then
        echo ERR: python3 not detected!
        ytbu_err
      else
        echo What?
        readerz=1
      fi
      reader=1
    fi
  done
}
ytbu_config_nodes(){
  reader=1
  while [[ $reader == 1 ]]; do
    read -p "Use multiple nodes(computers)? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      nodes=1
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      nodes=0
      reader=0
    else
      echo What?
      reader=1
    fi
  done
}
ytbu_configure(){ #run functions and save the final config
  ytbu_config_installcheck
  ytbu_config_wdir
  ytbu_config_webhooky
  ytbu_config_nodes
  echo wdir="$wdir" > $wdir/.ytbu.cfg #save config to config file
  echo py3="$py3" >> $wdir/.ytbu.cfg
  echo ydl="$ydl" >> $wdir/.ytbu.cfg
  echo webhooky_oauth="$webhooky_oauth" >> $wdir/.ytbu.cfg
  echo webhooky_complete="$webhooky_complete" >> $wdir/.ytbu.cfg
  echo webhooky_token="$webhooky_token" >> $wdir/.ytbu.cfg
  echo nodes="$nodes" >> $wdir/.ytbu.cfg
  echo "Configuration complete!"
}

############################## MAIN ##############################
ytbu_main(){
  echo welcome to the empty main
}
ytbu_channelfetch(){
  if [ ! -f ./ytbu.cfg ]; then #check if there is any configuration
    echo ERR: No configuration set!
    ytbu_err
  else
    :
  fi
  source ./ytbu.cfg # Read configuration
  cd $wdir #incase if all else fails
  if [ ! -f $wdir/client_secret.json ]; then # check if it exists
    ytbu_secret
    echo ERR: No client_secret.json found!
    ytbu_err
  else
    :
  fi
  rm -f $wdir/.ytbu_tmp_nextpager.py $wdir/.ytbu_channels.txt # clean up from previous run
  ytbu_channelsget # Get a list of channels
}
ytbu_getlist(){
  #rm
  $ydl -j --flat-playlist --batch-file $wdir/.ytbu_channels.txt --download-archive $wdir/ytbu_downloaded.txt | jq -r '.id' | sed 's_^_https://youtu.be/_' > $wdir/.ytbu_master.txt
}
ytbu_nodes(){
  if [[ "$nodes" == 1 ]]; then #check for multinode
    if [[ "$head" == 1 ]]; then #is this node the head?
      echo Head of office in your service
      wc -l $wdir/.ytbu_master.txt
    else
      echo Just a worker
    fi
  else
    echo lonely
  fi
}

ytbu_threads(){
  echo "test"
}

ytbu_threadend(){
  echo "test"
}


############################## ARGUMENTS / MENU ##############################
ytbu_mainargs(){
  if [ "$1" = "" ]; then
    ytbu_main
  elif [ "$1" = "install" ]; then
    ytbu_install
    exit
  elif [ "$1" = "go" ]; then
    ytbu_secret
    ytbu_install
    ytbu_configure
    read -n1 -r -p "If you have your client_secret.json in the working directory, press any key to continue..." key
    ytbu_main
  elif [ "$1" = "configure" ]; then
    ytbu_configure
    exit
  elif [ "$1" = "secret" ]; then
    ytbu_secret
    exit
  elif [ "$1" = "help" ]; then
    ytbu_err
  else
    echo ERR: Invalid argument!
    ytbu_err
  fi
}

ytbu_mainargs "$1"
