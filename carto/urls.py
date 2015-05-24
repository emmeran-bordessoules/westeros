from django.conf.urls import patterns, url

urlpatterns = patterns('carto.views',
    url(r'^$', 'home'),
)