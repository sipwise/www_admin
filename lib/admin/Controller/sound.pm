package admin::Controller::sound;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::sound - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

Edit sound sets.

=cut

sub base : Chained('/') PathPrefix CaptureArgs(0) {
    my ($self, $c) = @_;
    return unless ( $c->stash->{sets} = $c->forward ('load_sets'));
    
    if (defined $c->session->{refill}) {
        foreach my $s (@{$c->stash->{sets}}) {
            next if ($s->{id} ne $c->session->{refill}->{set_id});
            foreach my $h (@{$s->{handles}}) {
                next if ($h->{id} ne $c->session->{refill}->{handle_id});
                $h->{filename} = $c->session->{refill}->{filename};
                $h->{err} = 1; 
            }
        }
        $c->session->{refill} = undef;
    }
    
    $c->stash->{template} = 'tt/sound.tt';
}

sub list : Chained('base') PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound.tt';
}

sub set_get : Chained('base') PathPart('set') CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;
    $c->stash->{set_id} = $set_id if ($set_id != 0);
}

sub set_add : Chained('base') PathPart('set') CaptureArgs(0) {
    my ($self, $c, $set_id) = @_;
}

sub handle_get : Chained('set_get') PathPart('handle') CaptureArgs(1) {
    my ($self, $c, $handle_id) = @_;
    $c->stash->{handle_id} = $handle_id;
}

sub upload_soundfile : Chained('handle_get') PathPart('soundfile/upload') Args(0) {
    my ($self, $c) = @_;
    my %messages;

    my $upload = $c->req->upload('soundfile');
    my ($file, $filename);
    if (defined $upload) {
        $file = eval { $upload->slurp };
        $filename = eval { $upload->filename };
    }

# ne radi :(
#     my $checkresult; 
#     return unless $c->model('Provisioning')->call_prov( $c, 'voip',
#         'check_filetype',
#         { filetype => 'audio/x-wav',
#           file => $file,
#         },
#         \$checkresult
#     );
 
    # if ($checkresult) {
    use File::Type;
    my $ft = File::Type->new();
    if ($ft->checktype_contents($file) eq 'audio/x-wav') {
        
        if ($c->model('Provisioning')->call_prov($c, 'voip',
            'add_sound_file',
            { set_id => $c->stash->{set_id},
              handle_id => $c->stash->{handle_id},
              soundfile => $file,
              filename => $filename,
            },
            undef))
        {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
        } else {
            $messages{toperr} = 'Client.Voip.InputErrorFound';
        }
    } 
    else {
        $messages{file_err} = 'Client.Syntax.InvalidFileType';
        $c->session->{refill} = { set_id => $c->stash->{set_id}, handle_id => $c->stash->{handle_id}, filename => $filename };
    }
    
    $c->session->{messages} = \%messages;
    $c->response->redirect('/sound/set/' . $c->stash->{set_id} . '/edit#set_' . $c->stash->{set_id});
}

sub get_soundfile : Chained('handle_get') PathPart('soundfile/get') Args(0) {
    my ($self, $c) = @_;
   
    my $soundfile;
    if ($c->model('Provisioning')->call_prov($c, 'voip',
        'get_sound_file',
        { set_id => $c->stash->{set_id},
          handle_id => $c->stash->{handle_id},
        },
        \$soundfile))
    {}

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $soundfile->{filename} . '"');
    $c->response->body($soundfile->{data});
}

sub edit_set : Chained('set_get') PathPart('edit') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{edit_set_id} = $c->stash->{set_id}; # meh
    $c->stash->{template} = 'tt/sound.tt';
}

sub delete_set : Chained('set_get') PathPart('delete') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound.tt';
    my %messages;
        
    if ($c->model('Provisioning')->call_prov($c, 'voip',
        'delete_sound_set',
        { id => $c->stash->{set_id} },
        undef))
    {
        $messages{topmsg} = 'Server.Voip.SoundsetDeleted';
    }
    else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
    }
    
    $c->response->redirect("/sound");
}

# deletes an sound file, not the handle
# usage of 'handle' here is from users perspective
sub delete_handle : Chained('handle_get') PathPart('delete') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound.tt';
    my %messages;
        
    if ($c->model('Provisioning')->call_prov($c, 'voip',
        'delete_sound_file',
        { set_id => $c->stash->{set_id},
          handle_id => $c->stash->{handle_id}
        },
        undef))
    {
        $messages{topmsg} = 'Server.Voip.SoundHandleDeleted';
    }
    else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
    }
    
    $c->response->redirect('/sound/set/' . $c->stash->{set_id} . '/edit#set_' . $c->stash->{set_id});
}

sub save_set : Chained('set_get') PathPart('save') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound.tt';
    
    my %messages;
    $c->stash->{set_name} = $c->request->params->{set_name};

    if ($c->stash->{set_id}) {
        if ($c->model('Provisioning')->call_prov($c, 'voip',
            'update_sound_set',
            { id => $c->stash->{set_id},
              set_name => $c->stash->{set_name},
            },
            undef))
        {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
        }
    }
    else {
        if ($c->model('Provisioning')->call_prov($c, 'voip',
            'create_sound_set',
            { set_name => $c->request->params->{set_name} },
            undef ))

        {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
        }
    }
 
    $messages{toperr} = 'Client.Voip.InputErrorFound';
    $c->response->redirect("/sound");
}

sub load_sets :Private {
    my ( $self, $c, $params) = @_;

    my $sets;
    return unless $c->model('Provisioning')->call_prov(
        $c,
        'voip',
        'get_sound_sets',
        # TODO: remove comment
        # handle_request (called from call_prov) will add
        # reseller_id
        # { reseller_id => $params->{reseller_id} },
        undef, # parameters
        \$sets,
    );

    return $sets;
}

# Ends, some people will rob their mothers for the ends ...
1
