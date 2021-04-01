# ==================================================
$system_packages = [
'apt-transport-https',
'clang',
'clang-9',
'clang-tools-9',
'clang-10',
'clang-tools-10',
'clang-11',
'clang-tools-11',
'curl',
'debian-archive-keyring',
'debian-keyring',
'emacs',
'gawk',
'git',
'make',
'net-tools',
'wget',
'zstd',
]

package { $system_packages:
  ensure => 'installed'
}

# ==================================================
package { "nginx":
  ensure => installed,
}

service { "nginx":
  ensure => running,
}

# ==================================================
vcsrepo { '/firejail':
  ensure => latest,
  provider => git,
  source => 'https://github.com/netblue30/firejail.git',
  revision => 'LTSbase',
}

exec { 'firejail-configure':
  command => '/firejail/configure',
  cwd => '/firejail',
  subscribe => Vcsrepo['/firejail'],
  refreshonly => true,
}

exec { 'firejail-make':
  command => '/usr/bin/make install-strip',
  cwd => '/firejail',
  subscribe => Vcsrepo['/firejail'],
  require   => Exec['firejail-configure'],
  refreshonly => true,
}

# ==================================================
exec { 'setup-node':
  command => '/usr/bin/curl -sL https://deb.nodesource.com/setup_12.x | /usr/bin/bash -',
  unless => '/usr/bin/ls /etc/apt/sources.list.d/nodesource.list',
} ->

package { 'nodejs':
  ensure => 'installed',
} ->

vcsrepo { '/ce':
  ensure => latest,
  provider => git,
  source => 'https://github.com/compiler-explorer/compiler-explorer.git',
  revision => '3c2aa307e1a2dbda3c6eb4ac6052a6a6689e6bd6',
} ->

file { '/ce/etc/config/execution.local.properties':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/execution.mozilla.properties'
} ->

file { '/ce/etc/config/c++.local.properties':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/c%2B%2B.mozilla.properties'
} ->

file { '/ce/views/resources/site-logo.svg':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/ce-mozilla.svg'
} ->

file { '/etc/systemd/system/ce.service':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/puppet/ce.service'
} ->

service { 'ce':
  ensure => running,
}

# ==================================================

exec { 'download-clang':
  command => '/usr/bin/wget -q https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/gecko.cache.level-1.toolchains.v3.linux64-clang-11.latest/artifacts/public/build/clang.tar.zst',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11'
} ->

exec { 'unzip-clang':
  command => '/usr/bin/unzstd clang.tar.zst',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11',
} ->

exec { 'untar-clang':
  command => '/usr/bin/tar xf clang.tar',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11',
} ->

exec { 'move-clang':
  command => '/usr/bin/mv clang mozilla-clang-11',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11',
}