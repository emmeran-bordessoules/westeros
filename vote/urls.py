from django.conf.urls import patterns, url

urlpatterns = patterns('vote.views',
    url(r'^$', 'home'),
	url(r'plusun/$','incrVote'),
	
)
