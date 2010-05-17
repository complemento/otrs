# --
# Kernel/Modules/AdminService.pm - admin frontend to manage services
# Copyright (C) 2001-2010 OTRS AG, http://otrs.org/
# --
# $Id: AdminService.pm,v 1.30 2010-05-17 18:30:46 en Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminService;

use strict;
use warnings;

use Kernel::System::Service;
use Kernel::System::Valid;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.30 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check all needed objects
    for (qw(ParamObject DBObject LayoutObject ConfigObject LogObject)) {
        if ( !$Self->{$_} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $_!" );
        }
    }
    $Self->{ServiceObject} = Kernel::System::Service->new(%Param);
    $Self->{ValidObject}   = Kernel::System::Valid->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # ------------------------------------------------------------ #
    # service edit
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'ServiceEdit' ) {
        my %ServiceData;

        # get params
        $ServiceData{ServiceID} = $Self->{ParamObject}->GetParam( Param => "ServiceID" );
        if ( $ServiceData{ServiceID} ne 'NEW' ) {
            %ServiceData = $Self->{ServiceObject}->ServiceGet(
                ServiceID => $ServiceData{ServiceID},
                UserID    => $Self->{UserID},
            );
        }

        # output header
        my $Output = $Self->{LayoutObject}->Header();
        $Output .= $Self->{LayoutObject}->NavigationBar();

        # output overview
        $Self->{LayoutObject}->Block(
            Name => 'Overview',
            Data => { %Param, },
        );

        $Self->{LayoutObject}->Block( Name => 'ActionList' );
        $Self->{LayoutObject}->Block( Name => 'ActionOverview' );

        # generate ParentOptionStrg
        my $TreeView = 0;
        if ( $Self->{ConfigObject}->Get('Ticket::Frontend::ListType') eq 'tree' ) {
            $TreeView = 1;
        }
        my %ServiceList = $Self->{ServiceObject}->ServiceList(
            Valid  => 0,
            UserID => $Self->{UserID},
        );
        $ServiceData{ParentOptionStrg} = $Self->{LayoutObject}->BuildSelection(
            Data           => \%ServiceList,
            Name           => 'ParentID',
            SelectedID     => $ServiceData{ParentID},
            PossibleNone   => 1,
            TreeView       => $TreeView,
            Sort           => 'TreeView',
            DisabledBranch => $ServiceData{Name},
            Translation    => 0,
            Max            => 200,
        );

        # get valid list
        my %ValidList        = $Self->{ValidObject}->ValidList();
        my %ValidListReverse = reverse %ValidList;

        $ServiceData{ValidOptionStrg} = $Self->{LayoutObject}->BuildSelection(
            Data       => \%ValidList,
            Name       => 'ValidID',
            SelectedID => $ServiceData{ValidID} || $ValidListReverse{valid},
        );

        # output service edit
        $Self->{LayoutObject}->Block(
            Name => 'ServiceEdit',
            Data => { %Param, %ServiceData, },
        );

        # shows header
        if ( $ServiceData{ServiceID} ne 'NEW' ) {
            $Self->{LayoutObject}->Block( Name => 'HeaderEdit' );
        }
        else {
            $Self->{LayoutObject}->Block( Name => 'HeaderAdd' );
        }

        # show each preferences setting
        my %Preferences = ();
        if ( $Self->{ConfigObject}->Get('ServicePreferences') ) {
            %Preferences = %{ $Self->{ConfigObject}->Get('ServicePreferences') };
        }
        for my $Item ( sort keys %Preferences ) {
            my $Module = $Preferences{$Item}->{Module}
                || 'Kernel::Output::HTML::ServicePreferencesGeneric';

            # load module
            if ( !$Self->{MainObject}->Require($Module) ) {
                return $Self->{LayoutObject}->FatalError();
            }
            my $Object = $Module->new(
                %{$Self},
                ConfigItem => $Preferences{$Item},
                Debug      => $Self->{Debug},
            );
            my @Params = $Object->Param( ServiceData => \%ServiceData );
            if (@Params) {
                for my $ParamItem (@Params) {
                    $Self->{LayoutObject}->Block(
                        Name => 'Item',
                        Data => { %Param, },
                    );
                    if (
                        ref( $ParamItem->{Data} ) eq 'HASH'
                        || ref( $Preferences{$Item}->{Data} ) eq 'HASH'
                        )
                    {
                        $ParamItem->{'Option'} = $Self->{LayoutObject}->BuildSelection(
                            %{ $Preferences{$Item} },
                            %{$ParamItem},
                        );
                    }
                    $Self->{LayoutObject}->Block(
                        Name => $ParamItem->{Block} || $Preferences{$Item}->{Block} || 'Option',
                        Data => {
                            %{ $Preferences{$Item} },
                            %{$ParamItem},
                        },
                    );
                }
            }
        }

        # generate output
        $Output .= $Self->{LayoutObject}->Output(
            TemplateFile => 'AdminService',
            Data         => \%Param,
        );
        $Output .= $Self->{LayoutObject}->Footer();

        return $Output;
    }

    # ------------------------------------------------------------ #
    # service save
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ServiceSave' ) {

        # challenge token check for write action
        $Self->{LayoutObject}->ChallengeTokenCheck();

        # get params
        my %GetParam;
        for (qw(ServiceID ParentID Name ValidID Comment)) {
            $GetParam{$_} = $Self->{ParamObject}->GetParam( Param => $_ ) || '';
        }

        # save to database
        if ( $GetParam{ServiceID} eq 'NEW' ) {
            $GetParam{ServiceID} = $Self->{ServiceObject}->ServiceAdd(
                %GetParam,
                UserID => $Self->{UserID},
            );
            if ( !$GetParam{ServiceID} ) {
                return $Self->{LayoutObject}->ErrorScreen();
            }

        }
        else {
            my $Success = $Self->{ServiceObject}->ServiceUpdate(
                %GetParam,
                UserID => $Self->{UserID},
            );
            if ( !$Success ) {
                return $Self->{LayoutObject}->ErrorScreen();
            }
        }

        # update preferences
        my %ServiceData = $Self->{ServiceObject}->ServiceGet(
            ServiceID => $GetParam{ServiceID},
            UserID    => $Self->{UserID},
        );
        my %Preferences = ();
        if ( $Self->{ConfigObject}->Get('ServicePreferences') ) {
            %Preferences = %{ $Self->{ConfigObject}->Get('ServicePreferences') };
        }
        for my $Item ( sort keys %Preferences ) {
            my $Module = $Preferences{$Item}->{Module}
                || 'Kernel::Output::HTML::ServicePreferencesGeneric';

            # load module
            if ( !$Self->{MainObject}->Require($Module) ) {
                return $Self->{LayoutObject}->FatalError();
            }

            my $Object = $Module->new(
                %{$Self},
                ConfigItem => $Preferences{$Item},
                Debug      => $Self->{Debug},
            );
            my $Note;
            my @Params = $Object->Param( ServiceData => \%ServiceData );
            if (@Params) {
                my %GetParam = ();
                for my $ParamItem (@Params) {
                    my @Array = $Self->{ParamObject}->GetArray( Param => $ParamItem->{Name} );
                    $GetParam{ $ParamItem->{Name} } = \@Array;
                }
                if ( !$Object->Run( GetParam => \%GetParam, ServiceData => \%ServiceData ) ) {
                    $Note .= $Self->{LayoutObject}->Notify( Info => $Object->Error() );
                }
            }
        }

        # redirect to overview
        return $Self->{LayoutObject}->Redirect( OP => "Action=$Self->{Action}" );
    }

    # ------------------------------------------------------------ #
    # service overview
    # ------------------------------------------------------------ #
    else {

        # output header
        my $Output = $Self->{LayoutObject}->Header();
        $Output .= $Self->{LayoutObject}->NavigationBar();

        # check if service is enabled to use it here
        if ( !$Self->{ConfigObject}->Get('Ticket::Service') ) {
            $Output .= $Self->{LayoutObject}->Notify(
                Priority => 'Error',
                Data     => '$Text{"Please activate %s first!", "Service"}',
                Link =>
                    '$Env{"Baselink"}Action=AdminSysConfig;Subaction=Edit;SysConfigGroup=Ticket;SysConfigSubGroup=Core::Ticket#Ticket::Service',
            );
        }

        # output overview
        $Self->{LayoutObject}->Block(
            Name => 'Overview',
            Data => { %Param, },
        );

        $Self->{LayoutObject}->Block( Name => 'ActionList' );
        $Self->{LayoutObject}->Block( Name => 'ActionAdd' );

        # output overview result
        $Self->{LayoutObject}->Block(
            Name => 'OverviewList',
            Data => { %Param, },
        );

        # get service list
        my %ServiceList = $Self->{ServiceObject}->ServiceList(
            Valid  => 0,
            UserID => $Self->{UserID},
        );

        # if there are any services defined, they are shown
        if (%ServiceList) {

            # get valid list
            my %ValidList = $Self->{ValidObject}->ValidList();

            # add suffix for correct sorting
            for ( keys %ServiceList ) {
                $ServiceList{$_} .= '::';
            }
            for my $ServiceID ( sort { $ServiceList{$a} cmp $ServiceList{$b} } keys %ServiceList ) {

                # get service data
                my %ServiceData = $Self->{ServiceObject}->ServiceGet(
                    ServiceID => $ServiceID,
                    UserID    => $Self->{UserID},
                );

                # output row
                if ( $Self->{ConfigObject}->Get('Ticket::Frontend::ListType') eq 'tree' ) {

                    # output row
                    $Self->{LayoutObject}->Block(
                        Name => 'OverviewListRow',
                        Data => {
                            %ServiceData,
                            Name  => $ServiceData{Name},
                            Valid => $ValidList{ $ServiceData{ValidID} },
                        },
                    );
                }
                else {

                    # output row
                    $Self->{LayoutObject}->Block(
                        Name => 'OverviewListRow',
                        Data => {
                            %ServiceData,
                            Valid => $ValidList{ $ServiceData{ValidID} },
                        },
                    );
                }
            }

        }

        # otherwise a no data found msg is displayed
        else {
            $Self->{LayoutObject}->Block(
                Name => 'NoDataFoundMsg',
                Data => {},
            );
        }

        # generate output
        $Output .= $Self->{LayoutObject}->Output(
            TemplateFile => 'AdminService',
            Data         => \%Param,
        );
        $Output .= $Self->{LayoutObject}->Footer();

        return $Output;
    }
}

1;
