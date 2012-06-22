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
}

sub list : Chained('base') PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{sets} = $c->forward ('load_sets');
    $c->stash->{template} = 'tt/sound.tt';
}

sub set : Chained('base') PathPart('set') CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;
    $c->stash->{set_id} = $set_id if ($set_id != 0);
    $c->stash->{set} = $c->forward ('load_single_set') if ($set_id != 0);
}

sub set_add : Chained('base') PathPart('set') CaptureArgs(0) {
    my ($self, $c, $set_id) = @_;
}

sub handle : Chained('set') PathPart('handle') CaptureArgs(1) {
    my ($self, $c, $handle_id) = @_;
    $c->stash->{handle_id} = $handle_id;
}

sub edit_handle : Chained('handle') PathPart('edit') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound_edit_files.tt';
}

sub save_handle : Chained('handle') PathPart('save') Args(0) {
    my ($self, $c) = @_;
    my %messages;
    $c->stash->{template} = 'tt/sound_edit_files.tt';

    my ($soundfile, $filename);
    my $upload = $c->req->upload('soundfile');

    if (defined $upload) {
        $soundfile = eval { $upload->slurp };
        $filename = eval { $upload->filename };
        
        use File::Type;
        my $ft = File::Type->new();

        unless ($ft->checktype_contents($soundfile) eq 'audio/x-wav') {
            ##$messages{sound_set_err} = 'Client.Syntax.InvalidFileType';
            $c->session->{messages} = {sound_set_err => 'Client.Syntax.InvalidFileType'};
            $c->session->{refill} = { set_id => $c->stash->{set_id}, handle_id => $c->stash->{handle_id}, filename => $filename };
            return;
        }
    }

    if ($c->model('Provisioning')->call_prov($c, 'voip',
        'update_sound_handle',
        { set_id => $c->stash->{set_id},
          handle_id => $c->stash->{handle_id},
          soundfile => $soundfile,
          filename => $filename, 
          loopplay => $c->request->params->{loopplay} eq 'on' ? 1 : 0,
        },
        undef))
    {
        $messages{sound_set_msg} = 'Server.Voip.SavedSettings';
    } else {
        $messages{sound_set_err} = 'Client.Voip.InputErrorFound';
    }
    
    $c->session->{messages} = \%messages;
    $c->response->redirect('/sound/set/' . $c->stash->{set_id} . '/edithandles');
}

sub get_soundfile : Chained('handle') PathPart('soundfile/get') Args(0) {
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

sub edit_set : Chained('set') PathPart('edit') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{sets} = $c->forward ('load_sets');
    $c->stash->{template} = 'tt/sound.tt';
}

sub edit_files : Chained('set') PathPart('edithandles') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound_edit_files.tt';
}

sub delete_set : Chained('set') PathPart('delete') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound.tt';
    my %messages;
        
    if ($c->model('Provisioning')->call_prov($c, 'voip',
        'delete_sound_set',
        { id => $c->stash->{set_id} },
        undef))
    {
        $messages{sound_set_msg} = 'Server.Voip.SoundsetDeleted';
    }
    else {
        $messages{sound_set_err} = 'Client.Voip.InputErrorFound';
    }
    
    $c->response->redirect("/sound");
}

# deletes an sound file, not the handle
# usage of 'handle' here is from users perspective
sub delete_handle : Chained('handle') PathPart('delete') Args(0) {
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
        $messages{sound_set_msg} = 'Server.Voip.SoundHandleDeleted';
    }
    else {
        $messages{sound_set_err} = 'Client.Voip.InputErrorFound';
    }
    
    $c->response->redirect('/sound/set/' . $c->stash->{set_id} . '/edithandles');
}

sub save_set : Chained('set') PathPart('save') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/sound.tt';
    
    my %messages;
    $c->stash->{set_name} = $c->request->params->{set_name};
    $c->stash->{set_description} = $c->request->params->{set_description};

    if ($c->stash->{set_id}) {
        if ($c->model('Provisioning')->call_prov($c, 'voip',
            'update_sound_set',
            { id => $c->stash->{set_id},
              set_name => $c->stash->{set_name},
              set_description => $c->stash->{set_description},
            },
            undef))
        {
            $messages{sound_set_msg} = 'Server.Voip.SavedSettings';
        }
    }
    else {
        if ($c->model('Provisioning')->call_prov($c, 'voip',
            'create_sound_set',
            { set_name => $c->request->params->{set_name},
              set_description => $c->stash->{set_description},
            },
            undef ))

        {
            $messages{sound_set_msg} = 'Server.Voip.SavedSettings';
        }
    }
 
    $messages{sound_set_err} = 'Client.Voip.InputErrorFound';
    $c->response->redirect("/sound");
}

sub load_sets :Private {
    my ($self, $c) = @_;

    my $sets;
    return unless $c->model('Provisioning')->call_prov(
        $c,
        'voip',
        'get_sound_sets',
        undef, # parameters
        \$sets,
    );

    return $sets;
}

sub load_single_set :Private {
    my ($self, $c) = @_;

    my $set;
    return unless $c->model('Provisioning')->call_prov(
        $c,
        'voip',
        'get_single_sound_set',
        { set_id => $c->stash->{set_id} },
        \$set,
    );

    return $set;
}

# Ends, some people will rob their mothers for the ends ...
1
