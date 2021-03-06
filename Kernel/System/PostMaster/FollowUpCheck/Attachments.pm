# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PostMaster::FollowUpCheck::Attachments;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{ParserObject} = $Param{ParserObject} || die "Got no ParserObject";

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # The first attachment in a MIME email in OTRS is currently the body,
    #   so ignore it for this follow up check.
    my @Attachments = $Self->{ParserObject}->GetAttachments();
    shift @Attachments;

    ATTACHMENT:
    for my $Attachment (@Attachments) {

        my $Tn = $TicketObject->GetTNByString( $Attachment->{Content} );
        next ATTACHMENT if !$Tn;

        my $TicketID = $TicketObject->TicketCheckNumber( Tn => $Tn );

        if ($TicketID) {
            return $TicketID;
        }
    }

    return;
}

1;
