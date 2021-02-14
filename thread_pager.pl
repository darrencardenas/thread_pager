#!/usr/bin/perl

#---------------------------------------------------------------------------------------------------
# Thread Pager
#---------------------------------------------------------------------------------------------------
# This script checks for new posts in a thread by the author (OP/original poster). If a new post 
# from the author is found, the thread information is emailed, and a text message is sent.
# Posts made by any other users are ignored.
#
# Requirements:
#    - Turn on "Allow less secure apps" in your Google Account preferences to enable sending
#      over Gmail SMTP.
#    - Modify the values in the "REQUIRED CUSTOMIZATIONS" section below.
#
# Procedure:
#    - Run the script using Perl 5 version 28 or higher.
#
# Usage: thread_pager.pl
#
#---------------------------------------------------------------------------------------------------

use strict;
use warnings;
use LWP::UserAgent;
use Web::Query;
use Email::Send::SMTP::Gmail;

#---------------------------------------------------------------------------------------------------
# REQUIRED CUSTOMIZATIONS
#---------------------------------------------------------------------------------------------------
use constant SENDER_USERNAME => 'sender@email.com';
use constant SENDER_PASSWORD => 'password';

my @recipients     = (
                       'recipient@email.com',
                       '1234567890@vtext.com',  # Email for text message
                     );
my @urls           = ('http://website/forum/');                     
my $watched_thread = q/thread_name/;
my $watched_author = q/author_username/;

# Use CSS selectors to search elements
my $selector_class  = '.class';
my $selector_thread = '[thread]';
my $selector_author = '[author]';
my $selector_poster = '[poster]';

#---------------------------------------------------------------------------------------------------
# Optional Customization
#---------------------------------------------------------------------------------------------------
use constant MAIL_SERVER     => 'smtp.gmail.com';
use constant MAIL_LAYER      => 'ssl';
use constant MAIL_PORT       => '465';
use constant MAIL_DELAY      => 5;  # Seconds
use constant MAIL_SUBJECT    => 'New post detected';
use constant HTML_FILE       => 'page.html';
use constant TIMESTAMP_FILE  => 'timestamp.txt';


&main();


#---------------------------------------------------------------------------------------------------
# main
#---------------------------------------------------------------------------------------------------
sub main
{
  my $body         = '';     # Email body
  my $fh           = undef;  # Filehandle
  my $sendEmail    = 0;      # Flag for sending emails
  my @thread_array = ();     # Contains all thread data
  
  my $datestring = localtime();
  print "$datestring\n";
  
  # Avoid different output encodings
  binmode STDOUT, ":encoding(UTF-8)";
  
  # Begin loop through all urls
  for my $url (@urls)
  {
    my $ua = new LWP::UserAgent;
    my $req = new HTTP::Request GET => $url;
    
    # Request web data
    my $res = $ua->request($req);
 
    # Check the response
    if ($res->is_success) 
    {
      # Write content to HTML file for debugging purposes
      open($fh, ">", HTML_FILE) or die "Unable to open file: ", HTML_FILE, "\n";
      print $fh $res->content;
      close($fh);    
    }
    else
    {
      die "Could not get content from $url\n";
    }
    
    # Create a new instance of the web query
    my $q = Web::Query->new_from_file(HTML_FILE) or
            die "Unable to create a new instance of Web::Query\n";

    # Get thread title
    $q->find($selector_class)->find($selector_thread)
      ->each(
              sub {
                    my $i = shift;
                    $thread_array[$i]{title} = $_->text;                   
                  }
            );      
            
    # Get author
    $q->find($selector_class)->find($selector_author)
      ->each(
              sub {
                    my $i = shift;
                    $thread_array[$i]{author} = $_->text;                   
                  }
            ); 

    # Get timestamp and last poster
    $q->find($selector_class)->find($selector_poster)      
      ->each(
              sub {
                    my $i = shift;
                    
                    $thread_array[$i]{timestamp} = $_->text; 

                    $_->attr('title') =~ /poster \((.*)\)/;
                    $thread_array[$i]{poster} = $1;
                  }
            );

    # Begin loop through all thread data
    for my $i (0 .. $#thread_array)
    { 
      # Display data
      printf "%3d: { ", $i;
      for my $role (sort keys %{$thread_array[$i]})      
      {
        print "$role=$thread_array[$i]{$role} ";      
      }
      print "}\n";
      
       # Search for the watched thread and author
      if (($thread_array[$i]->{title} =~ /$watched_thread/i) &&
          ($thread_array[$i]->{author} eq $watched_author) &&
          ($thread_array[$i]->{poster} eq $watched_author))
      {
        print "\nFound a match! => $thread_array[$i]->{title} by $thread_array[$i]->{author}\n";       
        
        # Handle date strings
        if ($thread_array[$i]->{timestamp} =~ /\d+\-\w+/)
        {         
          print "Date timestamp found: $thread_array[$i]->{timestamp}\n";
          
          # Only create the date timestamp once
          if (&isTimestampNew($thread_array[$i]->{timestamp}) == 1)
          {
            print "Writing date timestamp to file ", TIMESTAMP_FILE, " ...\n";
            
            # Force a new timestamp
            &writeTimestampFile($thread_array[$i]->{timestamp},
                                $thread_array[$i]->{title},
                                $thread_array[$i]->{poster}); 
          }
        }               
        # Handle time strings
        else
        {
          # Timestamp is new        
          if (&isTimestampNew($thread_array[$i]->{timestamp}) == 1)
          {     
            print "Timestamp is NEW\n";
          
            # Build the email body
            $body = $body . "Thread: $thread_array[$i]->{title}\n";
            $body = $body . "Poster: $thread_array[$i]->{poster}\n";
            $body = $body . "Timestamp: $thread_array[$i]->{timestamp}\n\n";    

            &writeTimestampFile($thread_array[$i]->{timestamp},
                                $thread_array[$i]->{title},
                                $thread_array[$i]->{poster});
            
            # Set email flag
            $sendEmail = 1;
            
            print "Email body: $body";
          }
          # Timestamp is old
          else
          {
            print "Timestamp is OLD\n";
          }
        }
        
      }
      
    }  # End loop through all thread data

  }  # End loop through all urls
    
  # Check if email should be sent
  if ($sendEmail == 1)
  {
    # Begin loop through all email recipients
    for my $recipient (@recipients)
    {
      &send_mail($recipient, MAIL_SUBJECT, $body);

      print "\nNotified: $recipient";
      
      sleep(MAIL_DELAY);
      
    }  # End loop through all email recipients
    
    print "\n";
    
  }

} # End of main()


#---------------------------------------------------------------------------------------------------
# Subroutine send_mail
#---------------------------------------------------------------------------------------------------
sub send_mail 
{
  my ($to, $subject, $body) = @_;

  my ($mail, $error) = Email::Send::SMTP::Gmail->new(-smtp=>MAIL_SERVER,
                                                     -layer=>MAIL_LAYER,
                                                     -port=>MAIL_PORT,
                                                     -login=>SENDER_USERNAME,
                                                     -pass=>SENDER_PASSWORD);
   
  print "session error: $error\n" unless ($mail != -1);
   
  $mail->send(-to=>$to, -subject=>$subject, -body=>$body);
   
  $mail->bye;  

} # End of send_mail()


#---------------------------------------------------------------------------------------------------
# Subroutine getSavedTimestamp
#
# Returns timestamp string
#---------------------------------------------------------------------------------------------------
sub getSavedTimestamp
{
  my $fh = undef;  # Filehandle
  my $line = ''; 

  # Check for timestamp file existence
  if (-e TIMESTAMP_FILE)
  {
    open($fh, "<", TIMESTAMP_FILE) or die "Unable to open file: ", TIMESTAMP_FILE, "\n";
    
    # First line is the timestamp
    $line = <$fh>;
    
    close($fh);

    # Strip leading and trailing whitespace
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
  }
  else
  {
    print "File not found: ", TIMESTAMP_FILE, "\n";
  }

  return $line;
  
} # End of getSavedTimestamp()


#---------------------------------------------------------------------------------------------------
# Subroutine isTimeStampNew
#
# Returns 1 if timestamp is new
# Returns 0 if timestamp is old
#---------------------------------------------------------------------------------------------------
sub isTimestampNew
{
  my $timestamp = $_[0];

  my $line = &getSavedTimestamp();

  # Check timestamp
  if ($timestamp eq $line)
  {
    # Timestamp is old    
    return 0;
  }
  
  # Timestamp must be new
  return 1;

} # End of isTimestampNew()


#---------------------------------------------------------------------------------------------------
# Subroutine writeTimestampFile
#---------------------------------------------------------------------------------------------------
sub writeTimestampFile
{
  my ($timestamp, $title, $poster) = @_;
  
  my $fh = undef;  # Filehandle
  
  open($fh, ">", TIMESTAMP_FILE) or die "Unable to open file: ", TIMESTAMP_FILE, "\n";

  print $fh "$timestamp\n";
  print $fh "$title\n";
  print $fh "$poster\n";

  close($fh);

} # End of writeTimestampFile()
