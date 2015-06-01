from django.conf.urls import patterns, include, url
from django.contrib import admin
from django.conf.urls.static import static
from django.conf import settings

urlpatterns = patterns('',
	url(r'^vote/',include('vote.urls')),
	url(r'^carto$',include('carto.urls')),
	url(r'^contact/',include('contact.urls')),
	url(r'^comment/',include('comment.urls')),
	url(r'^admin/', include(admin.site.urls)),
	url(r'^/',include('vote.urls')),
	url(r'^$','vote.views.accueil'),
)+static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
