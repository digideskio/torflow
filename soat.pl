#!/usr/bin/perl -w

# ZOMG SNAKES ON A TOR1111 - v0.0.5

use strict;
use IO::Socket;
use IO::Socket::INET;

my $META_PORT = "9052";
my $META_HOST = "127.0.0.1";

my $WORD_LIST = "./wordlist.txt";
my $CERT_DIR = "./certs";
my $DOC_DIR = "./docs";
my $USER_AGENT = "Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.8.1) Gecko/20061010 Firefox/2.0";
#my $USER_AGENT = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; .NET CLR 1.0.3705; .NET CLR 1.1.4322)";

#Privoxy is a bad idea since it rewrites shit that will mess with our 
#baseline md5s of html
my $SOCKS_PROXY = "127.0.0.1:9050";

my @TO_SCAN = ("ssl");
my $ALLOW_NEW_SSL_IPS = 1;

# doc and ppt may also be good ones to check.. They are frequently vulnerable
# also, since we automatically weed out dynamic content, you can also add
# php, cgi, etc to this list.. The multiple "all" filetypes mean 2 * 5 sets
# of results without a filetype. Hopefully we can snag some static php,
# shtml, cgi files.
my @FILETYPES = ("all", "all"); #"xpi", "exe", "msi", "doc", "ppt", "all", "all"); 
my $RESULTS_PER_TYPE = 3;

# Maxium number of tries before giving up on a URL
my $MAX_TRIES = 3; 

# Urls to fetch in addition to queried ones. 
# These should end in one of the @FILETYPES extensions so failures
# are stored properly.
my @DOC_URLS = (
#    "http://www.cypherpunks.ca/otr/index.html",
#    "http://www.cypherpunks.ca/otr/press/index.html"
);

my @HTTPS_SITES = (
        "www.paypal.com",
        "www.e-gold.com",
        "chase.com",
#        "bankusa.com",
#        "citibank.com",
#        "www.mailvault.com",
        "mail.google.com",
        "www.relakks.com",
        "www.hushmail.com",
        "login.yahoo.com",
        "www.fastmail.fm",
        "addons.mozilla.org"
);


my $LOG_LEVEL = "DEBUG";
my %log_levels = ("DEBUG", 0, "INFO", 1, "NOTICE", 2, "WARN", 3, "ERROR", 4);


my %mt_circ_sel_counts;
my %mt_strm_sel_counts;
my %mt_reason_counts;
my %mt_fail_counts;
my %mt_fail_totals; # actually 5 vars in metatroller

my %mt_suspect_circ_sel_counts;
my %mt_suspect_strm_sel_counts;
my %mt_suspect_reason_counts;
my %mt_suspect_counts;

my %total_circ_sel_counts;
my %total_strm_sel_counts;
my %total_reason_counts;
my %total_fail_counts;
my %total_fail_totals; # actually 5 vars in metatroller

my %total_suspect_circ_sel_counts;
my %total_suspect_strm_sel_counts;
my %total_suspect_counts;
my %total_suspect_reason_counts;


my %key_names;

sub plog
{
    my $level = shift;
    my $msg = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $year += 1900; # lame.
    $mon += 1;
    
    #print "$level \[$year-$mon-$mday $hour:$min:$sec\]: " . $msg if($log_levels{$level} >= $log_levels{$LOG_LEVEL})
    print "$level \[" . localtime() . "\]: " . $msg if($log_levels{$level} >= $log_levels{$LOG_LEVEL})
}

sub is_in
{
    my $element = shift;
    my $ary = shift;
    my $is_there = 0;
    foreach (@$ary) {
        if ($_ eq $element) {
            $is_there = 1;
            last;
        }
    }

    return $is_there;
}

sub compare_arrays {
    my ($first, $second) = @_;
    no warnings;  # silence spurious -w undef complaints
        return 0 unless @$first == @$second;
    for (my $i = 0; $i < @$first; $i++) {
        return 0 if $first->[$i] ne $second->[$i];
    }
    return 1;
}


sub get_doc_list
{
    my @words = &load_wordlist($WORD_LIST);
    my @returns = &get_url_list(@words);

    return @returns;
}

sub load_wordlist
{
    my @wordlist;

    open(WORDFILE, '<', $_[0]);
    while (<WORDFILE>) {s/\n//; s/\r//; push(@wordlist, $_);}
    close(WORDFILE);

    return @wordlist;
}

sub get_url_list
{
    my @wordlist = @_;
    my @returns;

    # Get a few URL's for each file type
    foreach (@FILETYPES) {
        my @prereturns;
        my @urls;
        my $type = $_;
        mkdir("$DOC_DIR/$_");

        my $numresults = $RESULTS_PER_TYPE;
        while($#prereturns+1 < $numresults) {

            my @queries = ($wordlist[int(rand(@wordlist))],
                    $wordlist[int(rand(@wordlist))],
                    $wordlist[int(rand(@wordlist))]);

            foreach(@queries) {
                my @queryret = &discover_urls($type, $_);
                foreach(@queryret) {
                    push(@prereturns, $_) if(not is_in($_, \@prereturns));
                }
            }
        }
        for(my $i = 0; $i < $numresults;) {
            my $url = $prereturns[int(rand(@prereturns))];
            if(not is_in($url, \@urls)) {
                push(@returns, $url);
                push(@urls, $url);
                $i++;
            }
        }
        plog "INFO", "URL List for $type:\n " . join("\n ", @urls) . "\n\n";
    }


    return @returns;
}


sub discover_urls
{
    my $filetype = shift;
    my $query = shift;
    my @results;
    my @returns;

    # Craft Google URL
    my $base_url = "http://www.google.com/search?q=";
    my $url;
    if($filetype eq "all") {
        $url = $base_url . $query;
    } else {
        $url = $base_url . $query . "+filetype%3A" . $filetype;
    }

    # Execute this query
    open(QUERY, '-|', "wget -T 600 -U \"$USER_AGENT\" \'$url\' -O - 2> /dev/null");
    #open(QUERY, '-|', "curl -A \"$USER_AGENT\" \'$url\' 2> /dev/null");
    @results = <QUERY>;
    close(QUERY);

    # Extract all valid URLS
    my $line = join('', @results);
    if($filetype eq "all") {
        @results = $line =~ /http:\/\/[^<>\s"]+/g;
    } else {
        @results = $line =~ /http:\/\/[^<>\?\&#"]+\.$filetype/g;
    }

    # Filter out links to google services and cgi
    foreach (@results) {
        if (not /oxyshare/) { #and not /google/) {
            push(@returns, $_);
        }
    }

    return @returns;
}

sub get_https_list()
{
    return \@HTTPS_SITES;    
}

sub query_exit
{
    my $mcp = shift;
    my $line;
    my $exit;
    print $mcp "GETLASTEXIT\r\n";
    $line = <$mcp>;
    $line =~ /LASTEXIT=([\S]+)/;
    $exit = $1;

    if($exit eq "0") {
        plog "NOTICE", "Got 0 exit\n";
    }
    
    return $exit;    
}

sub openssl_check_one
{
    my $mcp = shift;
    my $ssl_host = shift;
    my $cert_dir = shift;
    my $resolve = shift;
    my $empty_ssl = 1;
    my $resolv_exit;
    my $ssl_ip;
    my $fq_ssl;
    my @ssl_data;
    my @ssl_cert;
    my $i;


    if($resolve) {
        do {
            if(not open(TORRESOLVE, '-|', "tor-resolve $ssl_host $SOCKS_PROXY")) {
                die "Cant call tor-resolve for $ssl_host";
            }

            $ssl_ip = <TORRESOLVE>;
            chomp($ssl_ip) if($ssl_ip);
            close(TORRESOLVE);
            if(not $ssl_ip) {
                plog "NOTICE", "tor-resolve failed to resolve $ssl_host\n";
            }
        } while(not $ssl_ip or not $ssl_ip =~ /^[\d]+/);

        $resolv_exit = query_exit($mcp);

        # Redundant, but keeping in case we need to add a max_tries counter..
        if(not $ssl_ip or not $ssl_ip =~ /^[\d]+/) {
            plog "WARN", "tor-resolve failed to resolve $ssl_host\n";
            $ssl_ip = $fq_ssl = $ssl_host;
        } else {
            $fq_ssl = $ssl_host . "-" . $ssl_ip;
        }
    } else {
        $ssl_ip = $fq_ssl = $ssl_host;
    }
    
    my $cmd = "echo | tsocks openssl s_client -connect " . $ssl_ip . ":443 2> /dev/null";
    open(OPENSSL, '-|', $cmd);

    @ssl_data = <OPENSSL>;

    for($i = 0; $i <= $#ssl_data; $i++) {
        if($ssl_data[$i] =~ /BEGIN CERTIFICATE/) {
            $empty_ssl = 0;
            while(not $ssl_data[$i] =~ /END CERTIFICATE/) {
                push(@ssl_cert, $ssl_data[$i]);
                $i++;
            }
            push(@ssl_cert, $ssl_data[$i]);
            last;
        }
    }
    
    close(OPENSSL);

    if($empty_ssl) {
        my $exit_node = query_exit($mcp);
        plog "WARN", "$exit_node closed SSL for $fq_ssl before we got a cert\n";
        return 0;
    }

    my $cert_exists = 0;

    if(not ($cert_exists = open(CERTFILE, '<', $cert_dir . "/" . $fq_ssl . ".pem"))
            and $ALLOW_NEW_SSL_IPS) {
        plog "INFO", "Cert $fq_ssl never seen before. Storing it.\n";
        open(CERTFILE, '>', $cert_dir . "/" . $fq_ssl . ".pem");
        print CERTFILE @ssl_cert;
        close(CERTFILE);
    } else {
        my $exit_node = query_exit($mcp);    
        my @stored_cert;

        if($cert_exists) {
            @stored_cert = <CERTFILE>;
            close(CERTFILE);
        }
        
        if(not $exit_node eq $resolv_exit) {
            plog "NOTICE", "SSL fetch exit $exit_node is not the resolution exit ($resolv_exit)\n";
            $exit_node = $exit_node . "+" . $resolv_exit; 
        }
        
        if($cert_exists and compare_arrays(\@stored_cert, \@ssl_cert)) {
            plog "DEBUG", "Cert $fq_ssl OK\n";
        } else {

            if($cert_exists) {
                plog "WARN", "Error on cert $fq_ssl for exit $exit_node\n";
            } else {
                plog "WARN", "New unseen cert IP $fq_ssl for exit $exit_node\n";
            }
            my $i = 0;
            for($i = 0; (stat($cert_dir . "/ERRORS/" . $fq_ssl . ".pem-" . $exit_node . "-$i"))[0]; $i++) 
            { }

            open(CERTFILE, '>', $cert_dir . "/ERRORS/" . $fq_ssl . ".pem" . 
                    "-" . $exit_node . "-$i");
            print CERTFILE @ssl_data;
            close(CERTFILE);

        }

    }
    return 1;
}

sub openssl_check_all
{
    my $mcp = shift;
    my $ssl_list = shift;

    print $mcp "RESOLVEPORT 443\r\n";
    my $line = <$mcp>;
    die "Error setting resolution port: $line" if (not $line =~ /^250/);

    foreach(@$ssl_list) {    
        print $mcp "NEWEXIT\r\n";
        $line = <$mcp>;
        die "Error on newnym: $line\r\n" if(not $line =~ /^250/);
        for(my $try = 0; $try < $MAX_TRIES; $try++) {
            last if openssl_check_one($mcp, $_, $CERT_DIR, 1);
        }
    }
    plog "INFO", "Checked all SSL certs\n";
}

sub load_table
{
    my $table = shift;
    my $file = shift;
    my @hash_list;

    if(not open(TABLEFILE, '<', $file)) {
        return;
    }

    @hash_list = <TABLEFILE>;
    chomp(@hash_list);
    %$table = @hash_list;

    close(TABLEFILE);
}

sub write_table
{
    my $table = shift;
    my $file = shift;

    if(not open(TABLEFILE, '>', $file)) {
        die "Can't open $file to save md5 state table";
    }

    while (my($k,$v) = each %$table) {
        print TABLEFILE "$k\n$v\n";
    }

    close(TABLEFILE);
}

sub docs_check_one
{
    my $mcp = shift;
    my $doc_url = shift;
    my $md5_table = shift;
    my $doc_dir = shift;
    my $tsocks = shift;
    my $md5;
    my $exit_node = "unknown";
    my $line;

    plog "DEBUG", "$doc_url\n";
    my $ret = system("$tsocks wget -T 600 -U \"$USER_AGENT\" \'$doc_url\' -O $doc_dir/tmp-$tsocks >& /dev/null");
    #my $ret = 
    #    system("$tsocks curl -m 1200 -A \"$USER_AGENT\" \'$doc_url\' -o $doc_dir/tmp-$tsocks &> /dev/null");

    if($tsocks eq "") {
        $exit_node = "none. (Direct test)";
    } else {
        $exit_node = query_exit($mcp);
    }

    # TODO: It may be nice to make a metatroller REPORTFAILURE command
    # to cover the event where wget's internal timeout was triggered before
    # Tors. Download rate info would also be nice for stats.
    if($ret != 0) {
        if($ret == 2) {
            plog "NOTICE", "wget got SIGINT. Exiting\n";
            exit;
        }
        plog "NOTICE", "wget returned $? for |$doc_url| at $exit_node\n";
        return -1;
    }
   
    if(not open(MD5SUM, '-|', "md5sum $doc_dir/tmp-$tsocks")) {
        plog "WARN", "md5sum pipe failed for |$doc_url| at $exit_node\n";
        return -1;
    }

    $md5 = <MD5SUM>;
    if(not $md5) {
        plog "WARN", "Failed to read MD5 from pipe for |$doc_url| at $exit_node\n";
        return -1;
    }
    
    $md5 =~ s/[\s]*$doc_dir\/tmp-$tsocks$//;
    chomp($md5);

    close(MD5SUM);

    plog "DEBUG", " = $md5\n";

    if(not defined($$md5_table{$doc_url})) {
        $$md5_table{$doc_url} = $md5;
    } elsif (not $$md5_table{$doc_url} eq $md5) {
        my $new_url = $doc_url;

        $new_url =~ s/\//\\/g;
        $new_url =~ /\.([^\s\.]+)$/;
        my $extn = $1;
        if(not $extn or not is_in($extn, \@FILETYPES)) {
            $extn = "all";
        }

        
        if(not $tsocks eq "") {
            my $i = 0;

            if(not docs_check_one($mcp, $doc_url, $md5_table, $doc_dir, "")) {
                # Doc has actually changed.. 
                return 2;
            }
            
            for($i = 0; (stat("$doc_dir/$extn/$new_url-$exit_node-$i"))[0]; $i++) 
            { }
            rename("$doc_dir/tmp-$tsocks", "$doc_dir/$extn/$new_url-$exit_node-$i");
            plog "WARN", "Mismatch of md5 for $doc_url ($extn) at $exit_node (|$md5| vs |$$md5_table{$doc_url}|)\n";
        }

        return 0;
    }
    return 1;
}

sub docs_test_all
{
    my $mcp = shift;
    my $doc_list = shift;
    my $doc_dir = shift;
    my @killed;
    my %doc_table;
    my $md5;

    load_table(\%doc_table, $doc_dir . "/md5_table");
   
    for(my $i = 0; $i <= $#$doc_list; $i++) {
        if(docs_check_one($mcp, $$doc_list[$i], \%doc_table, $doc_dir, "") <= 0) {
            push(@killed, $$doc_list[$i]);
            splice(@$doc_list, $i, 1);
            $i--;
        }
    }

    write_table(\%doc_table, $doc_dir . "/md5_table");

    if($#killed >= 0) {
        plog "NOTICE", "Discarded " . ($#killed+1) . " dead/dynamic url(s):\n " . join("\n ", @killed) . "\n\n";
    }
}

sub docs_check_all
{
    my $mcp = shift;
    my $doc_list = shift;
    my $doc_dir = shift;
    my %doc_table;
    my $md5;

    print $mcp "RESOLVEPORT 80\r\n";
    my $line = <$mcp>;
    die "Error setting resolution port: $line" if (not $line =~ /^250/);

    load_table(\%doc_table, $doc_dir . "/md5_table");
    
    for(my $i = 0; $i <= $#$doc_list; $i++) {
        my $ret = 0;
        print $mcp "NEWEXIT\r\n";
        $line = <$mcp>;
        die "Error on newnym: $line\r\n" if(not $line =~ /^250/);
        for(my $try = 0; $try < $MAX_TRIES; $try++) {
            last if (($ret = docs_check_one($mcp, $$doc_list[$i], \%doc_table, $doc_dir, "tsocks")) >= 0);
        }

        if($ret == 2) {
            # Splice it. Change $i
            plog "NOTICE", $$doc_list[$i] . " has changed independent of Tor. Removing...\n";
            splice(@$doc_list, $i, 1);
            $i--;
        }
    }

    write_table(\%doc_table, $doc_dir . "/md5_table");
    plog "INFO", "Checked all urls\n";
}

sub openssh_check_one
{
    my $mcp = shift;
    my $key_file = shift;
    my $host = shift;
    my $resolve = shift;
    my $resolv_exit;
    my $host_ip;
    my $fq_host;
    my @usernames = ("root", "operator", "bin", "nobody", "sshd", "news");
    my @result;
    my $username = $usernames[int(rand(@usernames))];


    # TODO: http://www.monkey.org/~provos/scanssh/

    plog "DEBUG", "Host: |$host|\n";
    do {  
        if(not open(TORRESOLVE, '-|', "tor-resolve $host $SOCKS_PROXY")) {
            die "Cant call tor-resolve for $host";
        }

        $host_ip = <TORRESOLVE>;
        chomp($host_ip) if($host_ip);
        close(TORRESOLVE);
        if(not $host_ip or not $host_ip =~ /^[\d]+/) {
            plog "NOTICE", "tor-resolve failed to resolve |$host|\n";
        }

    } while(not $host_ip or not $host_ip =~ /^[\d]+/);

    $resolv_exit = query_exit($mcp);

    # Redundant, but maybe we want a max tries..
    if(not $host_ip or not $host_ip =~ /^[\d]+/) {
        plog "WARN", "tor-resolve failed to resolve |$host|\n";
        $host_ip = $fq_host = $host;
    } else {
        $fq_host = $host . "-" . $host_ip;
    }

    plog "DEBUG", "tsocks ssh -o UserKnownHostsFile=$key_file -o PreferredAuthentications=hostbased -o PasswordAuthentication=no -o StrictHostKeyChecking=yes $username\@$host_ip\n";
    if(not open(SSH, '-|', "tsocks ssh -o UserKnownHostsFile=$key_file -o PreferredAuthentications=hostbased -o PasswordAuthentication=no -o StrictHostKeyChecking=yes $username\@$host_ip 2>&1")) {
# \"/bin/ls >& /dev/null\"")) {
        plog "WARN", "ssh pipe failed for $fq_host\n";
        return -1;
    }
    
    @result = <SSH>;
    close(SSH);
    
    my $resline = join("", @result);
    my $exit_node = query_exit($mcp);

    if(not $exit_node eq $resolv_exit) {
        plog "NOTICE", "SSH fetch exit $exit_node is not the resolution exit ($resolv_exit)\n";
        $exit_node = $exit_node . "+" . $resolv_exit; 
    }
    
    plog "DEBUG", "Result: " . $resline . "\n";
    if($resline =~ /Connection refused/) {
        plog "NOTICE", "Connection refused for ssh host: $fq_host\n";
        return -1;
    }

    if(not $resline =~ /Permission denied/
            and not $resline =~ /Connection closed by/
            and not $resline =~ /Write failed: Broken pipe/) {
        my $i = 0;
        my $line;

        plog "WARN", "SSH error for $fq_host via $exit_node\n";

        for($i = 0; (stat("$DOC_DIR/ssh/$fq_host-$exit_node-$i"))[0]; $i++) 
        { }

        if(not open(ERR, '>', "$DOC_DIR/ssh/$fq_host-$exit_node-$i")) {
            plog "WARN", "Can't save ssh error in $DOC_DIR/ssh/$fq_host-$exit_node-$i\n";
            return -1;
        }
        
        print ERR "$resline\n";
        close(ERR);
        return 0;
    }
    return 1;
}

sub openssh_check_all
{
    my $mcp = shift;
    my $key_file = shift;
        
    mkdir("$DOC_DIR/ssh");

    if(not open(KEYFILE, '<', $key_file)) {
        return;
    }

    print $mcp "RESOLVEPORT 22\r\n";
    my $line = <$mcp>;
    die "Error setting resolution port: $line" if (not $line =~ /^250/);

    while(<KEYFILE>) {
        next if(/^10\./ or /^192.168/ or /^127/ or /^172/);
        /^([^,\s]+)/;
        my $host = $1; 

        if(not $host) {
            plog "WARN", "No ssh host found in $_\n";
            next;
        }
        
        print $mcp "NEWEXIT\r\n";
        $line = <$mcp>;
        die "Error on newnym: $line\r\n" if(not $line =~ /^250/);
        openssh_check_one($mcp, $key_file, $host);
    }
    
    plog "INFO", "Checked all ssh hosts\n";
}

sub parse_failrates
{
    my $file = shift;
    my $hash_fail = shift;
    my $hash_circ = shift;
    my $hash_strm = shift;
    my $hash_totals = shift;

    while(1) {
        my $line = <$file>;
        
        if($line =~ /^250 FAILCOUNT/) {
            $line =~ /FAILCOUNT ([\S]+) \(([\S]+)\) = ([\d]+)\//;
            my $key = $1;
            my $name = $2;
            my $fail = $3;
            # Hack because for reason failure lines there is an extra element
            # (middle=total failures)
            $line =~ /\/([\d]+)\+([\d]+)/;
            my $circ_sel = $1;
            my $strm_sel = $2;

            if($key_names{$key} and (not $key_names{$key} eq $name)) {
                plog "NOTICE", "$name for $key is not the same as $key_names{$key}\n";
            }
            $key_names{$key} = $name;
            if($$hash_fail{$key}) {
                $$hash_fail{$key} += $fail;
            } else {
                $$hash_fail{$key} = $fail;
            }

            if($hash_circ) {
                if($$hash_circ{$key}) {
                    $$hash_circ{$key} += $circ_sel;
                } else {
                    $$hash_circ{$key} = $circ_sel;
                }
            }
            if($hash_strm) {
                if($$hash_strm{$key}) {
                    $$hash_strm{$key} += $strm_sel;
                } else {
                    $$hash_strm{$key} = $strm_sel;
                }
            }

        } else {
            if($hash_totals) {
                if($line =~ /^250 FAILTOTALS ([\d]+)\/([\d]+) ([\d]+)\+([\d]+)\/([\d]+)/) {
                    $$hash_totals{"CIRCUITFAILED"} = $1;
                    $$hash_totals{"CIRCUITCOUNTS"} = $2;
                    $$hash_totals{"STREAMDETACHED"} = $3;
                    $$hash_totals{"STREAMFAILURES"} = $4;
                    $$hash_totals{"STREAMCOUNTS"} = $5;
                    plog "DEBUG", "Got fail totals\n";
                }
            }
            last;
        }
    }
}

sub read_failrates
{
    my $mcp = shift;
    my $file = shift;
    my $cmd = shift;
    my $mt_fcnt = shift;
    my $tot_fcnt = shift; 
    my $mt_circ_sel_cnt = shift;
    my $tot_circ_sel_cnt = shift;
    my $mt_strm_sel_cnt = shift;
    my $tot_strm_sel_cnt = shift;
    my $mt_totals = shift;
    my $tot_totals = shift;
    
    return;
    # Hack to avoid counting previous run
    print $mcp "$cmd\r\n";
    parse_failrates($mcp, $mt_fcnt, $mt_circ_sel_cnt, $mt_strm_sel_cnt, $mt_totals);

    if(not open(FAILFILE, '<', $file)) {
        return;
    }

    parse_failrates(*FAILFILE, $tot_fcnt, $tot_circ_sel_cnt, $tot_strm_sel_cnt, $tot_totals);
    close(FAILFILE);
}

sub write_failrates
{
    my $mcp = shift;
    my $file = shift;
    my $cmd = shift;
    my $mt_fcnt = shift;
    my $tot_fcnt = shift;
    my $mt_circ_sel_cnt = shift;
    my $tot_circ_sel_cnt = shift;
    my $mt_strm_sel_cnt = shift;
    my $tot_strm_sel_cnt = shift;
    my $mt_totals = shift;
    my $tot_totals = shift;
    my %fail_counts;
    my %circ_counts;
    my %strm_counts;
    my %rate_totals;
    return;

    print $mcp "$cmd\r\n";
    parse_failrates($mcp, \%fail_counts, \%circ_counts, \%strm_counts, \%rate_totals);

    # Get delta
    foreach(keys(%fail_counts)) {
        if(not $$tot_fcnt{$_}) {
            $$tot_circ_sel_cnt{$_} = 0;
            $$tot_strm_sel_cnt{$_} = 0;
            $$tot_fcnt{$_} = 0;
        }

        if(not $$mt_fcnt{$_}) {
            $$mt_fcnt{$_} = 0;
            $$mt_circ_sel_cnt{$_} = 0;
            $$mt_strm_sel_cnt{$_} = 0;
        }

        # Update our totals only if the change is positive (ie no restart)
        if(($fail_counts{$_} - $$mt_fcnt{$_}) > 0) {
            $$tot_fcnt{$_} += ($fail_counts{$_} - $$mt_fcnt{$_});
            $$tot_circ_sel_cnt{$_} += ($circ_counts{$_} - $$mt_circ_sel_cnt{$_});
            $$tot_strm_sel_cnt{$_} += ($strm_counts{$_} - $$mt_strm_sel_cnt{$_});
        }

        # Store MT totals
        $$mt_fcnt{$_} = $fail_counts{$_};
        $$mt_circ_sel_cnt{$_} = $circ_counts{$_};
        $$mt_strm_sel_cnt{$_} = $strm_counts{$_};
    }

    if($tot_totals) {
        
        if(($rate_totals{"STREAMCOUNTS"} - $$mt_totals{"STREAMCOUNTS"}) > 0) {

            $$tot_totals{"CIRCUITFAILED"} += 
                $rate_totals{"CIRCUITFAILED"} - $$mt_totals{"CIRCUITFAILED"};
            $$tot_totals{"CIRCUITCOUNTS"} +=
                $rate_totals{"CIRCUITCOUNTS"} - $$mt_totals{"CIRCUITCOUNTS"};
            $$tot_totals{"STREAMDETACHED"} +=
                $rate_totals{"STREAMDETACHED"} - $$mt_totals{"STREAMDETACHED"};
            $$tot_totals{"STREAMFAILURES"} +=
                $rate_totals{"STREAMFAILURES"} - $$mt_totals{"STREAMFAILURES"};
            $$tot_totals{"STREAMCOUNTS"} +=
                $rate_totals{"STREAMCOUNTS"} - $$mt_totals{"STREAMCOUNTS"};

        }
        $$mt_totals{"CIRCUITFAILED"} = $rate_totals{"CIRCUITFAILED"};
        $$mt_totals{"CIRCUITCOUNTS"} = $rate_totals{"CIRCUITCOUNTS"};
        $$mt_totals{"STREAMDETACHED"} = $rate_totals{"STREAMDETACHED"};
        $$mt_totals{"STREAMFAILURES"} = $rate_totals{"STREAMFAILURES"};
        $$mt_totals{"STREAMCOUNTS"} = $rate_totals{"STREAMCOUNTS"};

    }

    # Use global, not arg (which may be undef)
    my @sorted_r = sort {
        $$tot_fcnt{$b} <=> $$tot_fcnt{$a}
    } keys %$tot_fcnt;

    if(not open(FAILFILE, '>', $file)) {
        die "Can't open $file to save fail rate table";
    }

    foreach(@sorted_r) {
        print FAILFILE "250 FAILCOUNT $_ ($key_names{$_}) = $$tot_fcnt{$_}/$$tot_circ_sel_cnt{$_}+$$tot_strm_sel_cnt{$_}\n";
    }

    if($tot_totals) { 
        print FAILFILE "250 FAILTOTALS " . $$tot_totals{"CIRCUITFAILED"} ."/". 
            $$tot_totals{"CIRCUITCOUNTS"} ." ". $$tot_totals{"STREAMDETACHED"} ."+". 
             $$tot_totals{"STREAMFAILURES"} ."/". $$tot_totals{"STREAMCOUNTS"} ." OK\n";
    } else { 
        print FAILFILE "250 OK\n";
    }
    
    close(FAILFILE);
    plog "INFO", "Updated failure counts\n";
}


sub parse_reasons
{
    my $file = shift;
    my $hash = shift;

    while( 1 ) {
        my $line = <$file>;
        my $reason;
        if($line =~ /^250 REASON=([\S]+)/) {
            $reason = $1;
        } elsif($line =~ /^250 OK/) {
            plog "DEBUG", "End reason parsing on $line\n";
            return;
        } else {
            plog "NOTICE", "Weird end line $line\n";
            return;
        }

        if(not $$hash{$reason}) {
            $$hash{$reason} = {};
        }

        parse_failrates($file, $$hash{$reason});
    }
}

sub read_reasons
{
    my $mcp = shift;
    my $file = shift;
    my $cmd = shift;
    my $mt_rc = shift;
    my $tot_rc = shift;
    return;

    # Hack to avoid double-counting
    print $mcp "$cmd\r\n";
    parse_reasons($mcp, $mt_rc);
    
    if(not open(FAILFILE, '<', $file)) {
        return;
    }

    parse_reasons(*FAILFILE, $tot_rc);
    close(FAILFILE);
}

sub write_reasons
{
    my $mcp = shift;
    my $file = shift;
    my $cmd = shift;
    my $mt_rcnt = shift;
    my $tot_rcnt = shift;
    my $tot_fcnt = shift;
    my $tot_circ_sel_cnt = shift;
    my $tot_strm_sel_cnt = shift;
    my %curr_reason_counts;

    return;
    print $mcp "$cmd\r\n";
    parse_reasons($mcp, \%curr_reason_counts);

    # Get delta
    foreach(keys(%curr_reason_counts)) {
        if(not $$tot_rcnt{$_}) {
            $$tot_rcnt{$_} = {};
        } 
        if(not $$mt_rcnt{$_}) {
            $$mt_rcnt{$_} = {};
        } 
        my $curr_hash = $curr_reason_counts{$_};
        my $total_hash = $$tot_rcnt{$_};
        my $mt_hash = $$mt_rcnt{$_};

        foreach(keys(%$curr_hash)) {

            if(not $$total_hash{$_}) {
                $$total_hash{$_} = 0;
            }

            if(not $$mt_hash{$_}) {
                $$mt_hash{$_} = 0;
            }

            # Update our totals 
            if(($$curr_hash{$_} - $$mt_hash{$_}) > 0) {
                $$total_hash{$_} += ($$curr_hash{$_} - $$mt_hash{$_});
            }

            # Store MT totals
            $$mt_hash{$_} = $$curr_hash{$_};
        }
    }

    my $failed_total = 0;
    foreach(keys(%$tot_fcnt)) {
        $failed_total += $$tot_fcnt{$_};
    }

    if(not open(FAILFILE, '>', $file)) {
        die "Can't open $file to save fail rate table";
    }

    foreach(keys(%$tot_rcnt)) {
        print FAILFILE "250 REASON=$_\r\n";
        my $reason_hash = $$tot_rcnt{$_};
        my $reason_total = 0;

        my @sorted_r = sort {
            $$reason_hash{$b} <=> $$reason_hash{$a}
        } keys %$reason_hash;

        foreach(@sorted_r) {
            print FAILFILE "250 FAILCOUNT $_ ($key_names{$_}) = $$reason_hash{$_}/$$tot_fcnt{$_}/$$tot_circ_sel_cnt{$_}+$$tot_strm_sel_cnt{$_}\r\n";
            $reason_total += $$reason_hash{$_};
        }
        print FAILFILE "250 REASONTOTAL $reason_total/$failed_total\r\n";
    }
    print FAILFILE "250 OK\r\n";
   
    close(FAILFILE);
    plog "INFO", "Updated failure counts\n";
}


sub main
{
    my $mcp = IO::Socket::INET->new(
            Proto    => "tcp",
            PeerAddr => $META_HOST,
            PeerPort => $META_PORT)
        or die "The Metatroller is not enabled";
    my $line = <$mcp>;
    $line = <$mcp>;

    print $mcp "PATHLEN 3\r\n";
    $line = <$mcp>;
    die "Error setting pathlen: $line" if (not $line =~ /^250/);
    print $mcp "PERCENTFAST 88\r\n";
    $line = <$mcp>;
    die "Error setting percentfast: $line" if (not $line =~ /^250/);
    print $mcp "USEALLEXITS 1\r\n";
    $line = <$mcp>;
    die "Error setting fastexits: $line" if (not $line =~ /^250/);
    print $mcp "UNIFORM 1\r\n";
    $line = <$mcp>;
    die "Error setting uniform: $line" if (not $line =~ /^250/);
    print $mcp "BWCUTOFF 1\r\n";
    $line = <$mcp>;
    die "Error setting BWCUTOFF: $line" if (not $line =~ /^250/);
    print $mcp "ORDEREXITS 1\r\n";
    $line = <$mcp>;
    die "Error setting ORDEREXITS: $line" if (not $line =~ /^250/);
    print $mcp "GUARDNODES 0\r\n";
    $line = <$mcp>;
    die "Error setting Guard Nodes: $line" if (not $line =~ /^250/);
    print $mcp "RESETSTATS\r\n";
    $line = <$mcp>;
    die "Error on RESETSTATS: $line" if (not $line =~ /^250/);
 
    delete $ENV{"http_proxy"};
    delete $ENV{"HTTP_PROXY"};
    delete $ENV{"proxy"};
    delete $ENV{"PROXY"};
   
    read_failrates($mcp, $DOC_DIR . "/naive_fail_rates",
            "FAILRATES", \%mt_fail_counts, \%total_fail_counts,
            \%mt_circ_sel_counts, \%total_circ_sel_counts,
            \%mt_strm_sel_counts, \%total_strm_sel_counts,
            \%mt_fail_totals, \%total_fail_totals);
    read_failrates($mcp, $DOC_DIR . "/suspected_rates",
            "SUSPECTRATES", \%mt_suspect_counts, \%total_suspect_counts,
            \%mt_suspect_circ_sel_counts, \%total_suspect_circ_sel_counts,
            \%mt_suspect_strm_sel_counts, \%total_suspect_strm_sel_counts);
    
    read_reasons($mcp, $DOC_DIR . "/naive_fail_reasons", 
            "FAILREASONS", \%mt_reason_counts, \%total_reason_counts);
    read_reasons($mcp, $DOC_DIR . "/suspected_reasons", 
            "SUSPECTREASONS", \%mt_suspect_reason_counts, 
            \%total_suspect_reason_counts);
  
    if(is_in("urls", \@TO_SCAN)) {   
        @DOC_URLS = (@DOC_URLS, get_doc_list());

        plog "INFO", "Checking doc list for dynamic content\n";
        
        # Perform 3 checks to eliminate obvious dynamic content
        docs_test_all($mcp, \@DOC_URLS, $DOC_DIR);
        docs_test_all($mcp, \@DOC_URLS, $DOC_DIR);
        docs_test_all($mcp, \@DOC_URLS, $DOC_DIR);
   
        plog "NOTICE", "Final URL List:\n " . join("\n ", @DOC_URLS) . "\n\n";
    }
    plog "INFO", "Beginning scan loop\n";
        
    while(1) {
        my $scan = $TO_SCAN[int(rand(@TO_SCAN))];
        plog "DEBUG", "Looped\n";
        if($scan eq "ssl") {
            openssl_check_all($mcp, \@HTTPS_SITES);
        } elsif($scan eq "urls") {
            docs_check_all($mcp, \@DOC_URLS, $DOC_DIR);
            if($#DOC_URLS <= (($#FILETYPES+1) * $RESULTS_PER_TYPE)/2) {
                plog "NOTICE", "Adding more URLS\n";
                @DOC_URLS = (@DOC_URLS, get_doc_list());
                docs_test_all($mcp, \@DOC_URLS, $DOC_DIR);
                docs_test_all($mcp, \@DOC_URLS, $DOC_DIR);
                docs_test_all($mcp, \@DOC_URLS, $DOC_DIR);
            }
        } elsif($scan eq "ssh") {
            openssh_check_all($mcp, "./known_hosts");
        }

        write_failrates($mcp, $DOC_DIR . "/naive_fail_rates", 
                "FAILRATES", \%mt_fail_counts, \%total_fail_counts, 
                \%mt_circ_sel_counts, \%total_circ_sel_counts,
                \%mt_strm_sel_counts, \%total_strm_sel_counts,
                \%mt_fail_totals, \%total_fail_totals);
        write_failrates($mcp, $DOC_DIR . "/suspected_rates", 
                "SUSPECTRATES", \%mt_suspect_counts, \%total_suspect_counts,
                \%mt_suspect_circ_sel_counts, \%total_suspect_circ_sel_counts,
                \%mt_suspect_strm_sel_counts, \%total_suspect_strm_sel_counts);
        
        write_reasons($mcp, $DOC_DIR . "/naive_fail_reasons",
                "FAILREASONS", \%mt_reason_counts, \%total_reason_counts,
                \%total_fail_counts, \%total_circ_sel_counts, \%total_strm_sel_counts);
        write_reasons($mcp, $DOC_DIR . "/suspected_reasons",
                "SUSPECTREASONS", \%mt_suspect_reason_counts,
                \%total_suspect_reason_counts, \%total_suspect_counts,
                \%total_suspect_circ_sel_counts,
                \%total_suspect_strm_sel_counts);
    }
}

main();