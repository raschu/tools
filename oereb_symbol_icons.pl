use strict;
use warnings;
use Spreadsheet::XLSX;
use File::Basename;
use LWP::UserAgent;
use MIME::Base64;
use utf8;
use DBI;

#V3 schreibt direkt in PG, ohne Umwege via SQLite und FME
#$WIDTH und $HEIGHT bei Bedarf anpassen
#$base_url evtl. noch anpassen

my $connection_string = "dbi:Pg:dbname=db;host=localhost;port=54351";
my $dbhpg = DBI->connect($connection_string, "user", "password");

print "Folgende Verbindung wird verwendet:\n$connection_string\nweiter mit Enter, Ctrl+C zum Abbrechen\n";
<STDIN>;

my $WIDTH = 51; #Breite des Symbols
my $HEIGHT= 30; #Höhe des Symbols
my $base_url = 'https://map-d.geo.sz.ch/uschaettin/wsgi/mapserv_proxy?username=intranet&FORMAT=image%2Fpng&TRANSPARENT=TRUE&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetLegendGraphic&EXCEPTIONS=application%2Fvnd.ogc.se_xml&LAYER=';
my $dbh;
my $dir = dirname(__FILE__);
my $excel = Spreadsheet::XLSX -> new ('LegendEntryInput.xlsx');

my %topic = (
    'a020' => 'Kataster belasteter Standorte',
    'a013' => 'Grundwasserschutzzone',
    'a051' => 'Nutzungsplanung kantonal (Natur- und Heimatschutz)',
    'a062' => 'Nutzungsplanung kantonal (Siedlung)',
    'a053' => 'statische Waldgrenze',
    'a063' => 'Nutzungsplanung kantonal (Strassen)',
    'a005' => 'Nutzungsplan kommunal',
    'a021' => 'Lärmempfindlichkeitsstufen',
    'a054' => 'Waldabstandslinien',
);


open(HTML, ">icons$WIDTH". "x" . "$HEIGHT.html");
print HTML "<html lang=\"de\">\n";
print HTML "  <head>\n";
print HTML "    <meta charset=\"utf-8\">\n";
print HTML "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n";
print HTML "    <title>OEREB Icons Schwyz</title>\n";
print HTML "  </head>\n";
print HTML "<pre>\n";

unlink("LegendEntryOutput_$WIDTH" . "_x" . "$HEIGHT.sl3") if -e "LegendEntryOutput_$WIDTH" . "_x" . "$HEIGHT.sl3";
truncate_data();

foreach my $sheet (@{$excel -> {Worksheet}}) {

    my $cnt = 0;
    my $lcnt = 0;
    
    if ($sheet->{Name} eq 'Tabelle1') {
    
        foreach my $row ($sheet -> {MinRow} .. $sheet -> {MaxRow}) {
            $cnt++;
            next if $cnt == 1; #erste Zeile ist Titel...
            
            $lcnt++;
            
            my $ID             = $sheet -> {Cells} [$row] [0] -> {Val};
            my $ViewServiceID  = $sheet -> {Cells} [$row] [1] -> {Val};
            my $symbol_url     = $sheet -> {Cells} [$row] [5] -> {Val};
            my $legend_text    = $sheet -> {Cells} [$row] [7] -> {Val};
            my $type_code      = $sheet -> {Cells} [$row] [6] -> {Val};
            my $topic          = $sheet -> {Cells} [$row] [4] -> {Val};
            my $pyramid_schema = $sheet -> {Cells} [$row] [3] -> {Val};
            my $Oereb_Thema    = $sheet -> {Cells} [$row] [2] -> {Val};
            my $type_code_list = 'dummy';
            my $topic_us;
            
            #land_use_plans_settlement wird vorderhand nocht nicht verwendet
            next if $pyramid_schema eq 'land_use_plans_settlement';
            
            print "xls_row #$cnt: $pyramid_schema [$ID]\n";
                        
            #um nur einzelne pyramid_schema zu testen, bitte eine der folgenden Zeilen aktivieren (ohne Kommentar):
            #OK,  erledigt: 21.11.2017 next unless ($pyramid_schema eq 'forest_distance_lines');   
            #OK,  erledigt: 21.11.2017 next unless ($pyramid_schema eq 'noise_sensitivity_levels');
            #NOK, fehlt noch FME Update: next unless ($pyramid_schema eq 'land_use_plans');
            #NOK, fehlt noch FME Update: next unless ($pyramid_schema eq 'forest_perimeters');
            #NOK, fehlt noch FME Update: next unless ($pyramid_schema eq 'groundwater_protection_zones');
            #NOK, fehlt noch FME Update: next unless ($pyramid_schema eq 'groundwater_protection_sites');
            #NOK, fehlt noch FME Update: next unless ($pyramid_schema eq 'land_use_plans_protection');
            #NOK, fehlt noch FME Update und auch view_service: next unless ($pyramid_schema eq 'contaminated_sites');
            ############################################################################
            
            my $symbol = get_base64_string_of_icon($symbol_url);
            my $themennummer = substr($symbol_url, 6, 4);
            
            $legend_text =~ s/%26auml%3B/ä/g;
            $legend_text =~ s/%26uuml%3B/ü/g;
                       
            if ($topic eq 'GroundwaterProtectionSites') {
                $legend_text = "{\"de\": \"Grundwasserschutzareale\"}";
            } else {
                $legend_text = "{\"de\": \"$legend_text\"}";
            }
            
            print HTML "$lcnt <img border=\"1\" src=\"data:image/png;base64," . $symbol . "\"/> $symbol_url <br>\n";
            
            $dbhpg->do("INSERT INTO $pyramid_schema.legend_entry
                    (id, view_service_id, symbol, legend_text, type_code, topic, type_code_list) 
                        VALUES 
                   ('$ID','$ViewServiceID','$symbol','$legend_text','$type_code','$topic', 'http://models.geo.sz.ch');");
            
            
        }
    }
}


sub get_base64_string_of_icon {

    my $s = shift;
    my $ua = LWP::UserAgent->new;
    my $req =  HTTP::Request->new( GET => $base_url . $s . "&WIDTH=$WIDTH&HEIGHT=$HEIGHT");
    my $res = $ua->request( $req );

    my $http_status_code = $res->status_line;

    if ($http_status_code eq "200 OK") {
        my $imgstring = encode_base64($res->decoded_content);
        return($imgstring);
    } else {
        return($http_status_code);
    }
}


sub truncate_data {
    $dbhpg->do("TRUNCATE forest_distance_lines.legend_entry;");
    $dbhpg->do("TRUNCATE noise_sensitivity_levels.legend_entry;");
    $dbhpg->do("TRUNCATE land_use_plans.legend_entry;");
    $dbhpg->do("TRUNCATE forest_perimeters.legend_entry;");
    $dbhpg->do("TRUNCATE groundwater_protection_zones.legend_entry;");
    $dbhpg->do("TRUNCATE groundwater_protection_sites.legend_entry;");
    $dbhpg->do("TRUNCATE land_use_plans_protection.legend_entry;");
    $dbhpg->do("TRUNCATE contaminated_sites.legend_entry;");
}
