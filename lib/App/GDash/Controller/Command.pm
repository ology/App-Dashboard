package App::GDash::Controller::Command;

use Capture::Tiny qw(capture);
use Encoding::FixLatin::XS qw(fix_latin);
use HTTP::Simple qw(getstore);
use Mojo::DOM ();
use XML::RSS ();

use Exporter 'import';
our @EXPORT = qw(rss_cmd perl_cmd curl_cmd);

sub rss_cmd {
  my ($feed) = @_;
  my $content = '';
  my $rss_content = 'rss-content.xml';
  unlink $rss_content;
  _get_file($feed, $rss_content);
  if (-e $rss_content) {
    my $rss = XML::RSS->new;
    eval { $rss->parsefile($rss_content) };
    if ($@) {
      warn "Can't parse $rss_content: $@\n";
    }
    else {
      $content = '<ul>';
      my $n = 0;
      for my $item ($rss->{items}->@*) {
        $n++;
        my $text = $item->{title};
        unless ($text) {
          my $dom = Mojo::DOM->new($item->{description});
          $text = $dom->all_text;
          $text = substr($text, 0, 49) . '...';
        }
        $content .= qq|<li><a href="$item->{link}" target="_blank">$text</a></li>|;
        last if $n >= 20;
      }
      $content .= '</ul>';
    }
  }
  return $content;
}

sub perl_cmd {
  my ($code) = @_;
  my $command = "perl -Mojo -E'$code'";
  return 'Invalid' if $command =~ /\bsystem\b/;
  my ($stdout, $stderr) = capture { system($command) };
  chomp $stdout;
  return $stderr ? $stderr : $stdout;
}

sub curl_cmd {
  my ($code) = @_;
  my $command = "curl $code";
  my ($stdout) = capture { system($command) };
  chomp $stdout;
  return fix_latin($stdout);
}

sub _get_file {
    my ($url, $file) = @_;
    my $status = getstore($url, $file)
        or warn "Can't getstore $url to $file: $!\n";
    warn "Could not get $file from $url\n"
        if $status && $status != 200;
}

1;
