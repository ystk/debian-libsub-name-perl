/* Copyright (C) 2004, 2008  Matthijs van Duin.  All rights reserved.
 * Copyright (C) 2014, cPanel Inc.  All rights reserved.
 * This program is free software; you can redistribute it and/or modify
 * it under the same terms as Perl itself.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static MGVTBL subname_vtbl;

#ifndef PERL_MAGIC_ext
# define PERL_MAGIC_ext '~'
#endif

#ifndef SvMAGIC_set
#define SvMAGIC_set(sv, val) (SvMAGIC(sv) = (val))
#endif

#ifndef Newxz
#define Newxz(ptr, num, type)	Newz(0, ptr, num, type)
#endif

MODULE = Sub::Name  PACKAGE = Sub::Name

PROTOTYPES: DISABLE

void
subname(name, sub)
	char *name
	SV *sub
    PREINIT:
	CV *cv = NULL;
	GV *gv;
	HV *stash = CopSTASH(PL_curcop);
	char *s, *end = NULL;
	MAGIC *mg;
    PPCODE:
	if (!SvROK(sub) && SvGMAGICAL(sub))
		mg_get(sub);
	if (SvROK(sub))
		cv = (CV *) SvRV(sub);
	else if (SvTYPE(sub) == SVt_PVGV)
		cv = GvCVu(sub);
	else if (!SvOK(sub))
		croak(PL_no_usym, "a subroutine");
	else if (PL_op->op_private & HINT_STRICT_REFS)
		croak("Can't use string (\"%.32s\") as %s ref while \"strict refs\" in use",
		      SvPV_nolen(sub), "a subroutine");
	else if ((gv = gv_fetchpv(SvPV_nolen(sub), FALSE, SVt_PVCV)))
		cv = GvCVu(gv);
	if (!cv)
		croak("Undefined subroutine %s", SvPV_nolen(sub));
	if (SvTYPE(cv) != SVt_PVCV && SvTYPE(cv) != SVt_PVFM)
		croak("Not a subroutine reference");
	for (s = name; *s++; ) {
		if (*s == ':' && s[-1] == ':')
			end = ++s;
		else if (*s && s[-1] == '\'')
			end = s;
	}
	s--;
        if (end) {
		char *namepv = savepvn(name, end - name);
		stash = GvHV(gv_fetchpv(namepv, TRUE, SVt_PVHV));
		Safefree(namepv);
                name = end;
        }

	/* under debugger, provide information about sub location */
	if (PL_DBsub && CvGV(cv)) {
		HV *hv = GvHV(PL_DBsub);
		SV** old_data;

		char* new_pkg = HvNAME(stash);

		char* old_name = GvNAME( CvGV(cv) );
		char* old_pkg = HvNAME( GvSTASH(CvGV(cv)) );

		int old_len = strlen(old_name) + strlen(old_pkg);
		int new_len = strlen(name) + strlen(new_pkg);

		char* full_name;
		Newxz(full_name, (old_len > new_len ? old_len : new_len) + 3, char);

		strcat(full_name, old_pkg);
		strcat(full_name, "::");
		strcat(full_name, old_name);

		old_data = hv_fetch(hv, full_name, strlen(full_name), 0);

		if (old_data) {
			strcpy(full_name, new_pkg);
			strcat(full_name, "::");
			strcat(full_name, name);

			SvREFCNT_inc(*old_data);
			if (!hv_store(hv, full_name, strlen(full_name), *old_data, 0))
				SvREFCNT_dec(*old_data);
		}
		Safefree(full_name);
	}

	gv = (GV *) newSV(0);
	gv_init(gv, stash, name, s - name, TRUE);

	mg = SvMAGIC(cv);
	while (mg && mg->mg_virtual != &subname_vtbl)
		mg = mg->mg_moremagic;
	if (!mg) {
		Newxz(mg, 1, MAGIC);
		mg->mg_moremagic = SvMAGIC(cv);
		mg->mg_type = PERL_MAGIC_ext;
		mg->mg_virtual = &subname_vtbl;
		SvMAGIC_set(cv, mg);
	}
	if (mg->mg_flags & MGf_REFCOUNTED)
		SvREFCNT_dec(mg->mg_obj);
	mg->mg_flags |= MGf_REFCOUNTED;
	mg->mg_obj = (SV *) gv;
	SvRMAGICAL_on(cv);
	CvANON_off(cv);
#ifndef CvGV_set
	CvGV(cv) = gv;
#else
	CvGV_set(cv, gv);
#endif
	PUSHs(sub);
