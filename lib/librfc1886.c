/*
 * Project    : ipv6calc
 * File       : librfc1886.c
 * Version    : $Id: librfc1886.c,v 1.5 2002/04/09 20:31:10 peter Exp $
 * Copyright  : 2002 by Peter Bieringer <pb (at) bieringer.de>
 *
 * Information:
 *  RFC 1886 conform reverse nibble format string
 *
 *  Function to format a given address to reverse nibble-by-nibble ip6.int|arpa format
 *
 * Intention from the Perl program "ip6_int" written by Keith Owens <kaos at ocs dot com dot au>
 * some hints taken from ifconfig.c (net-tools)
 * 
 * Credits to:
 *  Keith Owens <kaos at ocs dot com dot au>
 *	net-tools authors
 */

#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

#include "libipv6calcdebug.h"
#include "ipv6calctypes.h"
#include "libipv6addr.h"
#include "libipv6calc.h"
#include "librfc1886.h"


/*
 * converts IPv6addr_structure to a reverse nibble format string
 *
 * in : *ipv6addrp = IPv6 address structure
 * out: *resultstring = result
 * ret: ==0: ok, !=0: error
 */
#define DEBUG_function_name "librfc1886/addr_to_nibblestring"
int librfc1886_addr_to_nibblestring(ipv6calc_ipv6addr *ipv6addrp, char *resultstring, const uint32_t formatoptions, char* domain) {
	int retval = 1;
	unsigned int nibble;
	int bit_start, bit_end, nbit;
	char tempstring[NI_MAXHOST];
	unsigned int nnibble, noctett;
	
	if ( (ipv6calc_debug & DEBUG_librfc1886) != 0 ) {
		fprintf(stderr, "%s: flag_prefixuse %d\n", DEBUG_function_name, (*ipv6addrp).flag_prefixuse);
	};

	if ( ((formatoptions & (FORMATOPTION_printprefix | FORMATOPTION_printsuffix | FORMATOPTION_printstart | FORMATOPTION_printend)) == 0 ) && ((*ipv6addrp).flag_prefixuse != 0) ) {
		/* simulate old behavior */
		bit_start = 1;
		bit_end = (int) (*ipv6addrp).prefixlength;
		if ( (ipv6calc_debug & DEBUG_librfc1886) != 0 ) {
			fprintf(stderr, "%s: simulate old behavior\n", DEBUG_function_name);
		};
	} else if ( (*ipv6addrp).flag_startend_use != 0 ) {
		/* check start and end */
		if ( (((*ipv6addrp).bit_start - 1) & 0x03) != 0 ) {
			snprintf(resultstring, NI_MAXHOST, "Start bit number '%d' not dividable by 4 aren't supported because of non unique representation", ((*ipv6addrp).bit_start));
			retval = 1;
			return (retval);
		};
		if ( ((*ipv6addrp).bit_end & 0x03) != 0 ) {
			snprintf(resultstring, NI_MAXHOST, "End bit number '%d' not dividable by 4 aren't supported because of non unique representation", (*ipv6addrp).bit_end);
			retval = 1;
			return (retval);
		};

		bit_start = (int) (*ipv6addrp).bit_start;
		bit_end = (int) (*ipv6addrp).bit_end;
	} else {
		bit_start = 1;
		bit_end = 128;
	};
	
	if ( (ipv6calc_debug & DEBUG_librfc1886) != 0 ) {
		fprintf(stderr, "%s: start bit %d  end bit %d\n", DEBUG_function_name, bit_start, bit_end);
	};

	/* print out nibble format */
	/* 127 is lowest bit, 0 is highest bit */
	resultstring[0] = '\0';

	for (nbit = bit_end - 1; nbit >= bit_start - 1; nbit = nbit - 4) {
		/* calculate octett (8 bit) */
		noctett = ( ((unsigned int) nbit) & 0x78) >> 3;
		
		/* calculate nibble */
		nnibble = ( ((unsigned int) nbit) & 0x04) >> 2;

		/* extract nibble */
		nibble = ( (*ipv6addrp).in6_addr.s6_addr[noctett] & ( 0xf << (4 * (1 - nnibble)) ) ) >> ( 4 * (1 - nnibble));
		
		if ( (ipv6calc_debug & DEBUG_librfc1886) != 0 ) {
			fprintf(stderr, "%s: bit: %d = noctett: %u, nnibble: %u, octett: %02x, value: %x\n", DEBUG_function_name, nbit, noctett, nnibble, (unsigned int) (*ipv6addrp).in6_addr.s6_addr[noctett], nibble);
		};

		snprintf(tempstring, sizeof(tempstring), "%s%x", resultstring, nibble);
		if (nbit < bit_start) {
			snprintf(resultstring, NI_MAXHOST, "%s", tempstring);
		} else {
			snprintf(resultstring, NI_MAXHOST, "%s.", tempstring);
		};
	};

	if (bit_start == 1) {
		snprintf(tempstring, sizeof(tempstring), "%s%s", resultstring, domain);
	};

	snprintf(resultstring, NI_MAXHOST, "%s", tempstring);

	if ( (formatoptions & FORMATOPTION_printuppercase) != 0 ) {
		string_to_upcase(resultstring);
	};
		
	if ( (ipv6calc_debug & DEBUG_librfc1886) != 0 ) {
		fprintf(stderr, "%s: Print out: %s\n", DEBUG_function_name, resultstring);
	};

	retval = 0;
	return (retval);
};
#undef DEBUG_function_name


/*
 * function a reverse nibble format string into IPv6addr_structure
 *
 * in : inputstring
 * mod: *ipv6addrp = IPv6 address structure
 * ret: ==0: ok, !=0: error
 */
#define DEBUG_function_name "librfc1886/nibblestring_to_ipv6addrstruct"
int librfc1886_nibblestring_to_ipv6addrstruct(const char *inputstring, ipv6calc_ipv6addr *ipv6addrp, char *resultstring) {
	int retval = 1;
	char tempstring[NI_MAXHOST], *token, *cptr, **ptrptr;
	int flag_tld = 0, flag_nld = 0, tokencounter = 0;
	unsigned int noctet, nibblecounter = 0;
	int xdigit;

	ptrptr = &cptr;

	/* clear output structure */
	ipv6addr_clearall(ipv6addrp);

	/* reverse copy of string */
	snprintf(tempstring, sizeof(tempstring), "%s", inputstring);
	string_to_lowcase(tempstring);

	string_to_reverse(tempstring);	
	
	if ( (ipv6calc_debug & DEBUG_librfc1886) != 0 ) {
		fprintf(stderr, "%s: reverse copied string: %s\n", DEBUG_function_name, tempstring);
	};

	/* check string */
	retval = librfc1886_formatcheck(tempstring, resultstring);
	if (retval != 0) {
		return (1);
	};
	
	/* run through nibbles */
	token = strtok_r(tempstring, ".", ptrptr);

	while(token != NULL) {
		if (strcmp(token, "apra") == 0) {
			if (flag_tld == 0) {
				flag_tld = 1;
				goto NEXT_token_nibblestring_to_ipv6addrstruct;
			} else {
				snprintf(resultstring, NI_MAXHOST, "Top level domain 'arpa' is in wrong place");
				return (1);
			};
		};
		if (strcmp(token, "tni") == 0) {
			if (flag_tld == 0) {
				flag_tld = 1;
				goto NEXT_token_nibblestring_to_ipv6addrstruct;
			} else {
				snprintf(resultstring, NI_MAXHOST, "Top level domain 'int' is in wrong place");
				return (1);
			};
		};
		if (tokencounter == 1 && flag_tld == 1 && flag_nld == 0) {
			if (strcmp(token, "6pi") == 0) {
				flag_nld = 1;
				goto NEXT_token_nibblestring_to_ipv6addrstruct;
			} else {
				snprintf(resultstring, NI_MAXHOST, "Next level domain 'ip6' is in wrong place or missing");
				return (1);
			};
		};

		/* now proceed nibbles */
		if (strlen(token) > 1) {
			string_to_reverse(token);
			snprintf(resultstring, NI_MAXHOST, "Nibble '%s' on dot position %d (from right side) is longer than one char", token, tokencounter + 1);
			return (1);
		};
		
		if (! isxdigit(token[0])) {
			snprintf(resultstring, NI_MAXHOST, "Nibble '%s' on dot position %d (from right side) is not a valid hexdigit", token, tokencounter + 1);
			return (1);
		};

		retval = sscanf(token, "%x", &xdigit);
		if (retval != 1) {
			snprintf(resultstring, NI_MAXHOST, "Nibble '%s' on dot position %d (from right side) cannot be parsed", token, tokencounter + 1);
			return (1);
		};

		if ( xdigit < 0 || xdigit > 0xf ) {
			snprintf(resultstring, NI_MAXHOST, "Nibble '%s' on dot position %d (from right side) is out of range", token, tokencounter + 1);
			return (1);
		};

		noctet = nibblecounter >> 1; /* divided by 2 */
		
		if (noctet > 15) {
			snprintf(resultstring, NI_MAXHOST, "Too many nibbles");
			return (1);
		};

		if ( (nibblecounter & 0x01) != 0 ) {
			/* most significant bits */
			(*ipv6addrp).in6_addr.s6_addr[noctet] = ((*ipv6addrp).in6_addr.s6_addr[noctet] & 0xf0) | xdigit;
		} else {
			/* least significant bits */
			(*ipv6addrp).in6_addr.s6_addr[noctet] = ((*ipv6addrp).in6_addr.s6_addr[noctet] & 0x0f) | ((uint8_t) xdigit << 4);
		};

		nibblecounter++;
		
NEXT_token_nibblestring_to_ipv6addrstruct:
		token = strtok_r(NULL, ".", ptrptr);
		tokencounter++;
	};

	ipv6addrp->flag_valid = 1;
	ipv6addrp->flag_prefixuse = 1;
	ipv6addrp->prefixlength = (uint8_t) nibblecounter << 2;
	
	retval = 0;
	return (retval);
};
#undef DEBUG_function_name

/*
 * checks for proper format of a nibble string
 *
 * in : string
 * ret: ==0: ok, !=0: error
 */
#define DEBUG_function_name "librfc1886/formatcheck"
int librfc1886_formatcheck(const char *string, char *infostring) {
	size_t length;
	int nibblecounter = 0, flag_tld = 0, flag_nld = 0, tokencounter = 0;
	char tempstring[NI_MAXHOST], *token, *cptr, **ptrptr;

	ptrptr = &cptr;

	infostring[0] = '\0'; /* clear string */

        if (strlen(string) > sizeof(tempstring) - 1) {
		fprintf(stderr, "Input too long: %s\n", string);
		return (1);
	};

	strncpy(tempstring, string, sizeof(tempstring) - 1);
	
	length = strlen(tempstring);
	
	/* run through nibbles */
	token = strtok_r(tempstring, ".", ptrptr);

	while(token != NULL) {
		if (strcmp(token, "apra") == 0) {
			if (flag_tld == 0) {
				flag_tld = 1;
				goto NEXT_librfc1886_formatcheck;
			} else {
				snprintf(infostring, NI_MAXHOST, "Top level domain 'arpa' is in wrong place");
				return (1);
			};
		};
		if (strcmp(token, "tni") == 0) {
			if (flag_tld == 0) {
				flag_tld = 1;
				goto NEXT_librfc1886_formatcheck;
			} else {
				snprintf(infostring, NI_MAXHOST, "Top level domain 'int' is in wrong place");
				return (1);
			};
		};
		if (tokencounter == 1 && flag_tld == 1 && flag_nld == 0) {
			if (strcmp(token, "6pi") == 0) {
				flag_nld = 1;
				goto NEXT_librfc1886_formatcheck;
			} else {
				snprintf(infostring, NI_MAXHOST, "Next level domain 'ip6' is in wrong place or missing");
				return (1);
			};
		};

		/* now proceed nibbles */
		if (strlen(token) > 1) {
			string_to_reverse(token);
			snprintf(infostring, NI_MAXHOST, "Nibble '%s' on dot position %d (from right side) is longer than one char", token, tokencounter + 1);
			return (1);
		};
		
		if (! isxdigit(token[0])) {
			snprintf(infostring, NI_MAXHOST, "Nibble '%s' on dot position %d (from right side) is not a valid hexdigit", token, tokencounter + 1);
			return (1);
		};

		nibblecounter++;
		
		if (nibblecounter > 32) {
			snprintf(infostring, NI_MAXHOST, "Too many nibbles (more than 32)");
			return (1);
		};
		
NEXT_librfc1886_formatcheck:
		token = strtok_r(NULL, ".", ptrptr);
		tokencounter++;
	};

	return (0);
};
#undef DEBUG_function_name
