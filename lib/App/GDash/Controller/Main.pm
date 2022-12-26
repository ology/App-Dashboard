package App::GDash::Controller::Main;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Data::Dumper::Compact qw(ddc);
use HTTP::Simple qw(getstore);
use List::Util qw(first);
use Mojo::DOM ();
use Storable qw(retrieve store);
use XML::RSS ();

use constant DASHFILE => 'dashboard.dat';
use constant WIDTHS   => [4, 6, 8, 12];

sub index ($self) {
  my $cards;
  if (-e DASHFILE) {
    $cards = retrieve DASHFILE;
  }
  else {
    $cards = {
      1 => {id=>1,pos=>1,width=>8,title=>'A',text=>'Foo!'},
      2 => {id=>2,pos=>2,width=>4,title=>'B',text=>'Bar?'},
      3 => {id=>3,pos=>3,width=>6,title=>'C',text=>'Baz...'},
      4 => {id=>4,pos=>4,width=>6,title=>'D',text=>'Derp'},
    };
    store($cards, DASHFILE);
  }
  $self->render(
    cards  => $cards,
    max    => 12,
    min    => 4,
    widths => WIDTHS,
  );
}

sub update ($self) {
  my $cards;
  if (-e DASHFILE) {
    $cards = retrieve DASHFILE;
  }
  else {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  my $v = $self->validation;
  $v->required('cardId')->like(qr/^\d+$/);
  $v->required('cardTitle')->size(1, 50);
  $v->required('cardText')->size(1, 255);
  $v->required('cardPosition')->in(1 .. keys %$cards);
  $v->required('cardWidth')->in(WIDTHS->@*);
  if ($v->error('cardId')
    || $v->error('cardTitle') || $v->error('cardText')
    || $v->error('cardPosition') || $v->error('cardWidth')
  ) {
    $self->flash(error => 'Invalid update');
    return $self->redirect_to($self->url_for('index'));
  }
  my $id  = $v->param('cardId');
  my $pos = $v->param('cardPosition');
  if ($cards->{$id}{pos} != $pos) {
    my @by_id = sort { $cards->{$a}{pos} <=> $cards->{$b}{pos} } keys %$cards;
    my @reordered;
    my $n = 0;
    for my $i (@by_id) {
      $n++;
      next                 if $i == $id;
      push @reordered, $i  if $pos > $cards->{$id}{pos};
      push @reordered, $id if $n == $pos;
      push @reordered, $i  if $pos < $cards->{$id}{pos};
    }
    $n = 0;
    for my $i (@reordered) {
      $n++;
      $cards->{$i}{pos} = $n;
    }
  }
  $cards->{$id}{title} = $v->param('cardTitle');
  $cards->{$id}{text}  = $v->param('cardText');
  $cards->{$id}{width} = $v->param('cardWidth');

  if ($cards->{$id}{text} =~ /^http.+?\.rss$/) {
    my $rss_content = 'rss-content.xml';
    #_get_file($cards->{$id}{text}, $rss_content);
    my $rss = XML::RSS->new;
    $rss->parsefile($rss_content);
    my $content = '<ul>';
    for my $item ($rss->{items}->@*) {
      my $dom = Mojo::DOM->new($item->{description});
      my $text = $dom->all_text;
      $text = substr $text, 0, 49;
      $content .= qq|<li><a href="$item->{link}">$text...</a></li>|;
    }
    $content .= '</ul>';
    $cards->{$id}{content} = $content;
  }
  else {
    delete $cards->{$id}{content} if exists $cards->{$id}{content};
  }

  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub _get_file {
    my ($url, $file) = @_;
    my $status = getstore($url, $file)
        or die "Can't getstore $url to $file: $!\n";
    die "Could not get $file from $url\n"
        unless $status == 200;
}

sub delete ($self) {
  my $v = $self->validation;
  $v->required('cardId')->like(qr/^\d+$/);
  if ($v->error('cardId')) {
    $self->flash(error => 'Invalid update');
    return $self->redirect_to($self->url_for('index'));
  }
  my $id = $v->param('cardId');
  my $cards;
  if (-e DASHFILE) {
    $cards = retrieve DASHFILE;
  }
  else {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  delete $cards->{$id} if exists $cards->{$id};
  my @by_id = sort { $cards->{$a}{pos} <=> $cards->{$b}{pos} } keys %$cards;
  my $n = 0;
  for my $i (@by_id) {
    $n++;
    $cards->{$i}{pos} = $n;
  }
  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub new_card ($self) {
  my $v = $self->validation;
  $v->required('cardTitle')->size(1, 50);
  $v->required('cardText')->size(1, 255);
  $v->required('cardWidth')->in(WIDTHS->@*);
  if ($v->error('cardTitle') || $v->error('cardText') || $v->error('cardWidth')) {
    $self->flash(error => 'Invalid submission');
    return $self->redirect_to($self->url_for('index'));
  }
  my $cards;
  if (-e DASHFILE) {
    $cards = retrieve DASHFILE;
  }
  else {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  my $id = time();
  $cards->{$id} = {
    id    => $id,
    title => $v->param('cardTitle'),
    text  => $v->param('cardText'),
    width => $v->param('cardWidth'),
    pos   => keys(%$cards) + 1,
  };
  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub help ($self) { $self->render }

1;
