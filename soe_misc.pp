# Miscellaneous DEC-specific snippets that get rolled out everywhere
class dec::profiles::soe_misc {
  cron { 'inventory':
    ensure  => absent,
    command => '/software/bin/collectinv >/dev/null 2>&1',
    user    => root,
    hour    => '*',
    minute  => 05,
    require => Autofs::Mount['software'],
  }

  # Cater for old home dirs using u01 - make sure not on /
  file { '/u01':
    ensure => directory,
  }
  file { '/u01/home':
    ensure  => link,
    target  => '/home',
    require => File['/u01'],
  }

  # Some files have been marked immutable to stop cfengine touching them
  # 1. ew
  # 2. Keep this cronjob around until we've fully removed all such immutable
  #    files from our infrastructure.
  # 3. Delete the old cron.daily version of this check.
  cron { 'find-immutable':
    ensure  => present,
    command => '/usr/bin/lsattr -Ra 2>/dev/null /etc | awk \'$1 ~ /i/ && $1 !~ /^\// { print "Immutable_file="$2 }\' | logger -p local0.notice -t find_immutable', # lint:ignore:80chars
    user    => root,
    hour    => 3,
    minute  => 30,
  }
  file { '/etc/cron.daily/find-immutable':
    ensure => absent,
  }

  # Scan the /etc /usr/bin and /bin directories for files that are world
  # writable. Output to syslog so we can generate a report from Splunk.
  cron { 'find-worldwritable':
    ensure  => present,
    command => 'find /etc/ /usr/bin/ /bin/ -perm -2 ! -type l | awk \'{ print "file="$1 }\' | logger -p local0.notice -t find_worldwritable', # lint:ignore:80chars
    user    => root,
    hour    => 3,
    minute  => 45,
  }
  file { '/etc/cron.daily/find-worldwrite':
    ensure => absent,
  }

  # This isn't managed anywhere else, so here is good enough.
  file {
    '/opt/DET/sbin':
      ensure => directory,
      alias  => 'DETSBIN',
      owner  => 'root',
      group  => 'root',
      mode   => '0755';
    '/opt/DET/bin':
      ensure => directory,
      alias  => 'DETBIN',
      owner  => 'root',
      group  => 'root',
      mode   => '0755';
    '/etc/updatedb.conf':
      ensure  => 'present',
      content => template('dec/updatedb.conf.erb');
  }

  # These scripts are moving in from /software, an NFS share. Can't rely on
  # /software being mounted.
  file {
    # One day we can template LDAPHOSTS to use local servers in the datacentre.
    '/opt/DET/bin/netgroup':
      content => template('dec/bin/netgroup.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => File['DETBIN'];
  }

  # This is a fix for the Redhat 5 iptables module which produces a false negative error
  # See RH Case 01586301 for further details
  # For Red Hat 6 or other OS nothing will happen
  # For anthing else there will be a fail
  if $::osfamily == 'RedHat' and $::operatingsystemmajrelease == '5'
  {
    file { 'ip6tables-save':
        ensure => file,
        path   => '/sbin/ip6tables-save',
        source => 'puppet:///modules/dec/ip6tables-save',
        owner  => 'root',
        group  => 'root',
        mode   => '0744',
      }
    exec { 'ip6tables-save.orig':
        command => '/bin/mv /sbin/ip6tables-save /sbin/ip6tables-save.orig',
        onlyif  => '/usr/bin/test ! -f /sbin/ip6tables-save.orig',
        before  => File['ip6tables-save'],
    }
  }

  # Run rhn-profile-sync on boot to ensure that Satellite always has current
  # information. This is safe on all systems, if rhn-profile-sync doesn't exist
  # (eg. RHEL4) then it'll exit cleanly.
  file {
    '/usr/local/bin/satellite-sync':
      source  => 'puppet:///modules/dec/usr/local/bin/satellite-sync',
      owner   => 'root',
      group   => 'root',
      mode    => '0755';
    '/etc/cron.d/satellite-sync':
      content => "# THIS FILE IS MANAGED BY PUPPET, ANY LOCAL CHANGES WILL BE DESTROYED\n@reboot  root  /usr/local/bin/satellite-sync\n", # lint:ignore:80chars
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      require => File['/usr/local/bin/satellite-sync'];
  }
}
