package App::GDash::Controller::Main;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Data::Dumper::Compact qw(ddc);
use List::Util qw(first);
use Storable qw(retrieve store);

use constant DASHFILE => 'dashboard.dat';

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
    };
    store($cards, DASHFILE);
  }
  $self->render(
    cards => $cards,
    max   => 12,
    min   => 3,
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
  $v->required('cardPosition')->num;#(1, keys %$cards);
  $v->required('cardWidth')->in(4, 6, 8, 12);
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
  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub help ($self) { $self->render }

1;
