#!/usr/bin/perl
# 灵岛媒体适配器 —— 通过 Apple 签名二进制 /usr/bin/perl (bundle id: com.apple.perl5) 加载
# MediaRemoteAdapter.framework 读取「现在播放」信息。
#
# 为什么必须用 perl：macOS 15.4+ 起 MediaRemote 只允许 bundle identifier 以
# com.apple. 开头的进程读取 Now Playing（Apple 留下的过简检查）。应用自身进程
# 或应用衍生的子进程 dlopen 框架都会收到 "Operation not permitted"。而
# /usr/bin/perl 是 Apple 平台二进制，bundle id 为 com.apple.perl5，能通过检查。
# 原理见 ungive/mediaremote-adapter（BSD 3-Clause）。
#
# 用法:
#   mediaremote.pl <framework_path> stream
#   mediaremote.pl <framework_path> send <commandID>
#   mediaremote.pl <framework_path> seek <seconds>
#   mediaremote.pl <framework_path> test
#
# stream 模式常驻运行，把「现在播放」信息以 JSON lines 打印到 stdout。
# send / seek 为一次性命令（media 应用状态变更后，stream 进程会收到通知自动刷新）。

use strict;
use warnings;
use DynaLoader;
use IO::Select;
use POSIX qw(getppid);

my $framework_path = shift @ARGV;
my $mode = shift @ARGV;
die "usage: mediaremote.pl <framework> <stream|send|seek|test> [...]\n"
  unless defined $framework_path && defined $mode;

# framework 目录 → 实际 dylib 路径（macOS 26 上 dlopen 传目录会报 "(not a file)"）
my $fw = $framework_path;
$fw =~ s{/+$}{};
my ($name) = $fw =~ m{/([^/]+)\.framework$};
die "not a framework: $framework_path\n" unless $name;
my $binary;
for my $c ("$fw/$name", "$fw/Versions/Current/$name", "$fw/Versions/A/$name") {
  if (-e $c) { $binary = $c; last; }
}
die "framework binary not found under: $framework_path\n" unless $binary;

# 父进程（灵岛）退出 → stdin EOF → 结束自己，避免泄漏孤儿进程。
# adapter_stream 是阻塞调用，无法在本进程内同时读 stdin，故用 fork 出的 watchdog 监视。
# 必须在 dlopen 框架（会初始化 CoreFoundation）之前 fork，否则 watchdog 子进程继承
# CF 状态会触发 "The process has forked and you cannot use this CoreFoundation
# functionality safely" 告警。fork 失败时照常运行，仅失去防孤儿兜底。
my $watchdog_pid;
if ($mode eq 'stream') {
  $watchdog_pid = fork();
  if (defined $watchdog_pid && $watchdog_pid == 0) {
    my $sel = IO::Select->new(\*STDIN);
    while (1) {
      next unless $sel->can_read(1);
      my $n = sysread(STDIN, my $buf, 1);
      if (!defined $n || $n == 0) {
        kill 'TERM', getppid();
        exit 0;
      }
      # 有数据则丢弃（灵岛不写 stdin，仅用 EOF 作存活信号）
    }
  }
}

my $handle = DynaLoader::dl_load_file($binary, 0)
  or die "dl_load_file failed: $!\n";

sub load_xsub {
  my ($symbol, $into) = @_;
  my $s = DynaLoader::dl_find_symbol($handle, $symbol)
    or die "symbol $symbol not found\n";
  DynaLoader::dl_install_xsub("main::$into", $s);
}

# 框架环境选项：MEDIAREMOTEADAPTER_OPTION_<key>（key 中 '-' 归一化为 '_'）
sub set_option {
  my ($key, $value) = @_;
  $key =~ s/-/_/g;
  $ENV{"MEDIAREMOTEADAPTER_OPTION_$key"} = defined $value ? $value : "";
}

# 框架环境参数：MEDIAREMOTEADAPTER_PARAM_<fn>_<idx>_<name>
# 注意 fn 必须用不带 _env 后缀的名字（框架内部以此读取）
sub set_param {
  my ($fn, $idx, $name, $value) = @_;
  $ENV{"MEDIAREMOTEADAPTER_PARAM_${fn}_${idx}_${name}"} = $value;
}

if ($mode eq 'stream') {
  # 全量输出（非 diff），50ms 防抖。artworkData 必须保持 base64，勿开 human-readable。
  set_option('no_diff', '');
  set_option('debounce', '50');
  load_xsub('adapter_stream_env', 'do_stream');
  do_stream();
  kill 'TERM', $watchdog_pid if defined $watchdog_pid && $watchdog_pid > 0;
  exit 0;
}
elsif ($mode eq 'send') {
  my $cmd = shift @ARGV;
  die "missing command id\n" unless defined $cmd;
  set_param('adapter_send', 0, 'command', $cmd);
  load_xsub('adapter_send_env', 'do_send');
  do_send();
}
elsif ($mode eq 'seek') {
  my $seconds = shift @ARGV;
  die "missing seconds\n" unless defined $seconds;
  my $micros = int($seconds * 1_000_000);
  set_param('adapter_seek', 0, 'position', $micros);
  load_xsub('adapter_seek_env', 'do_seek');
  do_seek();
}
elsif ($mode eq 'test') {
  load_xsub('adapter_test', 'do_test');
  do_test();
}
else {
  die "unknown mode: $mode\n";
}
exit 0;
