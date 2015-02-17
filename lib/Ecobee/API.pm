#! /usr/bin/perl

package API;

use strict;
use warnings;
use WWW::Curl::Easy;
use JSON;
use Storable;

use constant DEBUG_TRACE => 0;
use constant DEBUG_IO => 0;

our $api_link = 'https://api.ecobee.com';
our $api_ver = '1';
our $api_key_file = 'api_key.txt';
our $authorize_file = 'authorize.dat';
our $token_file = 'token.dat';

our $api_key;
our $auto_mode = 0;
our $api_calls = 0;

sub Init {
  print("Init\n") if (DEBUG_TRACE);
  my ($p_data_directory, $p_auto_mode) = @_;

# Set auto negotiation mode (or fail)
  $auto_mode = $p_auto_mode;

# A data directory other than current directory has been specified
  if ($p_data_directory ne "") {
    $api_key_file   = "$p_data_directory/$api_key_file";
    $authorize_file = "$p_data_directory/$authorize_file";
    $token_file     = "$p_data_directory/$token_file";
  }

# Read the API key stored in file api_key.txt
  open(FILE, "<$api_key_file") || die "Cannot open api key file";
  $api_key = <FILE>;
  chomp($api_key);
  close(FILE);
}

sub Read_Authorize_Response {
  print("Read_Authorize_Response\n") if (DEBUG_TRACE);
  my ($p_hash_ref) = @_;
  my $retcode = 0;

  if (-e $authorize_file) {
    my $authorize_ref = Storable::retrieve($authorize_file);
    if (ref($authorize_ref) eq 'HASH') {
      %$p_hash_ref = %$authorize_ref;
      $retcode = 1;
    }
    else {
      unlink($authorize_file);
    }
  }

  return $retcode;
}

sub Write_Authorize_Response {
  print("Write_Authorize_Response\n") if (DEBUG_TRACE);
  my ($p_hash_ref) = @_;

  Storable::store($p_hash_ref, $authorize_file) || die "Cannot write authorize file";
}

sub Read_Token_Response {
  print("Read_Token_Response\n") if (DEBUG_TRACE);
  my ($p_hash_ref) = @_;
  my $retcode = 0;

  if (-e $token_file) {
    my $token_ref = Storable::retrieve($token_file);
    if (ref($token_ref) eq 'HASH') {
      %$p_hash_ref = %$token_ref;
      $retcode = 1;
    }
    else {
      unlink($token_file);
    }
  }

  return $retcode;
}

sub Write_Token_Response {
  print("Write_Token_Response\n") if (DEBUG_TRACE);
  my ($p_hash_ref) = @_;
  
  Storable::store($p_hash_ref, $token_file) || die "Cannot write token file";
}

# Submit low-level GET request through API
#
# Parameters: Header array ref (optional) (I)
#             API address scalar (I)
#             Command string scalar (I)
#             JSON details hash ref (optional) (I)
#             Hash reference (O)
#
# Return: http return code (200 = success)
#
sub API_Get_Request {
  print("API_Get_Request\n") if (DEBUG_TRACE);
  my ($p_hdr_ref, $p_api, $p_cmd, $p_json_ref, $p_hash_ref) = @_;

  my $response_body;
  my $error_buffer = "";

  my $curl = WWW::Curl::Easy->new;
  $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER, $p_hdr_ref) if (ref($p_hdr_ref) eq "ARRAY");

  my $url = $p_api.$p_cmd;
  if (ref($p_json_ref) eq "HASH") {
    my $json = JSON::encode_json($p_json_ref);
    $url = $url.$json;
  }
  print("URL: $url\n") if (DEBUG_IO);

  $curl->setopt(WWW::Curl::Easy::CURLOPT_URL, $url);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_WRITEDATA, \$response_body);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_ERRORBUFFER, "error_buffer");
  $curl->setopt(WWW::Curl::Easy::CURLOPT_SSL_VERIFYPEER, 1);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_VERBOSE, DEBUG_IO);

  if ($curl->perform != 0) {
    die "Curl failed: $error_buffer";
  }
  $api_calls++;

  print("Response body: $response_body\n") if (DEBUG_IO);

  my $response_code = $curl->getinfo(WWW::Curl::Easy::CURLINFO_HTTP_CODE);
  my $json_ref = JSON::decode_json($response_body);
  %$p_hash_ref = %$json_ref;

  return $response_code;
}

# Submit low-level POST request through API
#
# Parameters: Header array ref (optional) (I)
#             API address scalar (I)
#             Command string scalar (I)
#             JSON details hash ref (optional) (I)
#             Hash reference (O)
#
# Return: http return code (200 = success)
#
sub API_Post_Request {
  print("API_Post_Request\n") if (DEBUG_TRACE);
  my ($p_hdr_ref, $p_api, $p_cmd, $p_json_ref, $p_hash_ref) = @_;

  my $response_body;
  my $error_buffer = "";
  my $curl = WWW::Curl::Easy->new;

  $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER, $p_hdr_ref) if (ref($p_hdr_ref) eq "ARRAY");

  my $post;
  my $url;
  if (ref($p_json_ref) eq "HASH") {
    $url = $p_api.$p_cmd;
    $post = JSON::encode_json($p_json_ref);
  }
  else {
    $url = $p_api;
    $post = $p_cmd;
  }
  print("URL: $url\n") if (DEBUG_IO);
  print("POST: $post\n") if (DEBUG_IO);

  $curl->setopt(WWW::Curl::Easy::CURLOPT_URL, $url);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_POST, 1);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_POSTFIELDS, $post);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_WRITEDATA, \$response_body);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_ERRORBUFFER, "error_buffer");
  $curl->setopt(WWW::Curl::Easy::CURLOPT_SSL_VERIFYPEER, 1);
  $curl->setopt(WWW::Curl::Easy::CURLOPT_VERBOSE, DEBUG_IO);  

  if ($curl->perform != 0) {
    die "Curl failed: $error_buffer";
  }
  $api_calls++;

  print("Response body: $response_body\n") if (DEBUG_IO);

  my $response_code = $curl->getinfo(WWW::Curl::Easy::CURLINFO_HTTP_CODE);

  my $json_ref = JSON::decode_json($response_body);
  %$p_hash_ref = %$json_ref;

  return $response_code;
} 
 
sub Authorize_Request {
  print("Authorize_Request\n") if (DEBUG_TRACE);
  my ($p_hash_ref) = @_;

  my $endpoint = "$api_link/authorize";
  my $cmd = "?response_type=ecobeePin&client_id=$api_key&scope=smartWrite";
  my $retcode = API_Get_Request("", $endpoint, $cmd, "", $p_hash_ref);

  return $retcode;
}

sub Token_Request {
  print("Token_Request\n") if (DEBUG_TRACE);
  my ($p_code, $p_hash_ref) = @_;

  my $endpoint = "$api_link/token";
  my $cmd = "grant_type=ecobeePin&code=$p_code&client_id=$api_key";
  my $retcode = API_Post_Request("", $endpoint, $cmd, "", $p_hash_ref);

  return $retcode;
}

sub Refresh_Token_Request {
  print("Refresh_Token_Request\n") if (DEBUG_TRACE);
  my ($p_refresh, $p_hash_ref) = @_;

  my $endpoint = "$api_link/token";
  my $cmd = "grant_type=refresh_token&code=$p_refresh&client_id=$api_key";
  my $retcode = API_Post_Request("", $endpoint, $cmd, "", $p_hash_ref);

  return $retcode;
}

sub Get_Authorization {
  print("Get_Authorization\n") if (DEBUG_TRACE);
  my ($p_token_type_ref, $p_access_token_ref) = @_;

  my $retcode;
  my %token;
  if (!Read_Token_Response(\%token)) {
    if ($auto_mode) {
      print("Authorization failed. Needs to be re-established manually\n");
      exit (1);
    }

    my %authorize;
    if (!Read_Authorize_Response(\%authorize)) {
      $retcode = Authorize_Request(\%authorize);
      if ($retcode != 200) {
        die "Authorize request failed: $retcode";
      }
      Write_Authorize_Response(\%authorize);

      print("ecobeePin needs to be entered in web portal: $authorize{ecobeePin}\n");
      print("You have $authorize{expires_in} minutes to complete this operation\n");
      print("Re-launch application once it is completed\n");
      exit (1);
    }

    $retcode = Token_Request($authorize{code}, \%token);
    if ($retcode != 200) {
      unlink($authorize_file);
      print("Token acquisition failed: $retcode, re-launch application to start authorization again\n");
      exit (1);
    }
    Write_Token_Response(\%token);
  }

  $$p_token_type_ref = $token{token_type};
  $$p_access_token_ref = $token{access_token};
  return 1;
}

sub Get_Token_Refresh {
  print("Get_Token_refresh\n") if (DEBUG_TRACE);
  my ($p_token_type_ref, $p_access_token_ref) = @_;

  my $retcode;
  my %token;
  if (!Read_Token_Response(\%token)) {
    unlink($authorize_file);
    print("Token cannot be refreshed, re-launch application to start authorization again\n");
    exit (1);
  }

  $retcode = Refresh_Token_Request($token{refresh_token}, \%token);
  if ($retcode != 200) {
    unlink($authorize_file);
    unlink($token_file);
    print("Token refresh failed: $retcode, re-launch application to start authorization again\n");
    exit (1);
  }
  Write_Token_Response(\%token);

  $$p_token_type_ref = $token{token_type};
  $$p_access_token_ref = $token{access_token};
  return 1;
}

sub Get_Request {
  print("Get_Request\n") if (DEBUG_TRACE);
  my ($p_cmd, $p_json_ref, $p_hash_ref) = @_;

  my $token_type;
  my $access_token;
  Get_Authorization(\$token_type, \$access_token);

  my $retcode;
  my $cmd = "/$api_ver/$p_cmd?json=";
  do {
    my @header = ("Content-Type: application/json;charset=UTF-8",
                  "Authorization: $token_type $access_token");

    $retcode = API_Get_Request(\@header, $api_link, $cmd, $p_json_ref, $p_hash_ref);
    die "HTTP return code not successful: $retcode" if ($retcode != 200 && $retcode != 500);

    my %status = %{$$p_hash_ref{status}};
    $retcode = $status{code};

#   Authentication token has expired, request token refresh
    if ($retcode == 14) {
      Get_Token_Refresh(\$token_type, \$access_token);
    }
    elsif ($retcode != 0) {
      die "Get Request failed: $status{message}";
    }
  } while ($retcode != 0);
}

sub Post_Request {
  print("Post_Request\n") if (DEBUG_TRACE);
  my ($p_cmd, $p_json_ref, $p_hash_ref) = @_;

  my $token_type;
  my $access_token;
  Get_Authorization(\$token_type, \$access_token);

  my $retcode;
  my $cmd = "/$api_ver/$p_cmd?format=json";
  do {
    my @header = ("Content-Type: application/json;charset=UTF-8",
                  "Authorization: $token_type $access_token");

    $retcode = API_Post_Request(\@header, $api_link, $cmd, $p_json_ref, $p_hash_ref);
    die "HTTP return code not successful: $retcode" if ($retcode != 200 && $retcode != 500);

    my %status = %{$$p_hash_ref{status}};
    $retcode = $status{code};

#   Authentication token has expired, request token refresh
    if ($retcode == 14) {
      Get_Token_Refresh(\$token_type, \$access_token);
    }
    elsif ($retcode != 0) {
      die "Get Request failed: $status{message}";
    }
  } while ($retcode != 0);
}

sub API_Calls
{
  return ($api_calls);
}

1;
